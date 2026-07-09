//
//  RuleEnforcer.swift
//  OpenAppLock
//

import Foundation
import Observation

/// Turns the current set of rules into shield state: schedule rules with an
/// active, un-paused window are shielded, and limit rules whose daily budget
/// is spent (per the usage ledger) are shielded until midnight; everything
/// else is cleared.
///
/// Background transitions (and usage tracking itself) belong to the
/// DeviceActivity monitor extension; this keeps shields correct while the
/// app runs.
///
/// **Threading.** `refresh`/`pause`/`resume` do only the SwiftData-`@Model`
/// work (expiring pauses, confirming day-starts, snapshotting to
/// `RuleSnapshotDTO`) on the main actor, then hand the Sendable snapshots to
/// `RuleEnforcementEngine` — an actor that performs the shield and
/// DeviceActivity I/O **off** the main thread. This keeps the UI responsive:
/// `DeviceActivityCenter.startMonitoring` can block for tens of seconds, and it
/// must never do so on the main thread. Only `blockingRuleIDs` (the observed UI
/// state) is published back on the main actor.
@Observable
final class RuleEnforcer {
    private(set) var blockingRuleIDs: Set<UUID> = []
    /// Performs the shield + DeviceActivity I/O off the main thread and
    /// serializes overlapping refreshes (edit, 30 s loop, scenePhase).
    private let engine: RuleEnforcementEngine
    /// Keeps the pre-scheduled "a schedule rule starts in 5 minutes"
    /// notifications in step with the rules; nil in UI-test launches (and when
    /// the feature isn't wired). Driven off the same refresh funnel.
    private let notificationScheduler: NotificationScheduler?
    /// Day-usage source consulted for limit rules; also exposed to views for
    /// the Usage section (read synchronously on the main actor).
    let usageReader: UsageReading
    /// App-wide settings (currently just Uninstall Protection). Read on the main
    /// actor (it is `@Observable`, main-bound) and its value handed to the engine.
    private let settings: any AppSettingsReading
    /// Confirmed daily-activity starts; the foreground establishes today's start
    /// so a skipped monitor callback can't block usage recording all day.
    private let dayStarts: DayStartStore

    init(
        shields: ShieldApplying, usage: UsageReading = UsageLedger(),
        scheduler: RuleScheduler? = nil,
        notificationScheduler: NotificationScheduler? = nil,
        openSessions: OpenSessionReading = OpenSessionStore(),
        settings: any AppSettingsReading = AppSettingsStore(),
        dayStarts: DayStartStore = DayStartStore()
    ) {
        self.usageReader = usage
        self.notificationScheduler = notificationScheduler
        self.settings = settings
        self.dayStarts = dayStarts
        self.engine = RuleEnforcementEngine(
            shields: shields, scheduler: scheduler, usage: usage, openSessions: openSessions)
    }

    /// The day's usage for a rule (nil for schedule rules, which don't track).
    /// Synchronous main-actor accessor used by views; the engine reads usage
    /// independently for its off-main computation.
    func usage(
        for snapshot: RuleSnapshotDTO, at now: Date = .now, calendar: Calendar = .current
    ) -> RuleUsageDTO? {
        guard snapshot.kind != .schedule else { return nil }
        return usageReader.usage(for: snapshot.id, onDayContaining: now, calendar: calendar)
    }

    /// Recomputes shields from scratch. Call on launch, on any rule change,
    /// and periodically while the app is visible. Also expires stale pauses.
    ///
    /// The main-actor part is only the `@Model` work (pause expiry, day-start
    /// confirmation, snapshotting); the shield and DeviceActivity I/O runs on
    /// `engine` off the main thread, and `blockingRuleIDs` is published back here.
    ///
    /// **Overlapping rules — strictest enforcement wins.** Each rule shields its
    /// *own* `ManagedSettingsStore`, Screen Time unions shields across stores,
    /// and a rule only ever writes/clears its own store, so an app is blocked if
    /// *any* covering rule blocks it and rules never cancel each other out:
    /// whichever limit's budget is spent first blocks the app regardless of the
    /// other's remaining budget; an Allow-Only schedule cannot punch a hole
    /// through another rule's block (see `ShieldController`); and a temporary pause
    /// pauses only the rule it was invoked on. There is deliberately no central
    /// merge of selections — that would be the one place a block could be
    /// accidentally dropped.
    ///
    /// A rule is shielded when it is actively blocking (a schedule window is
    /// open, or a limit budget is spent) *or* when it is an open-limit rule
    /// that must gate its apps so opens can be counted.
    func refresh(rules: [BlockingRule], at now: Date = .now, calendar: Calendar = .current) async {
        let priorBlocking = blockingRuleIDs
        Diag.log(.enforcer, "refresh: \(rules.count) rules at \(LogTimestamp.string(from: now))")
        // Main actor: the only work that touches the SwiftData `@Model` — expire
        // stale pauses, confirm today's start, then flatten to Sendable snapshots.
        for rule in rules {
            expireStalePauseIfNeeded(rule, at: now)
            confirmForegroundDayStartIfNeeded(rule, at: now, calendar: calendar)
        }
        let snapshots = rules.map(\.dto)
        let uninstallProtectionEnabled = settings.uninstallProtectionEnabled
        // Off the main thread: all shield + DeviceActivity I/O (the multi-second
        // `startMonitoring` hang lives here).
        let outcome = await engine.apply(
            snapshots: snapshots, uninstallProtectionEnabled: uninstallProtectionEnabled,
            at: now, calendar: calendar)
        // Back on the main actor: publish the observed UI state.
        commitBlockingSet(outcome.blocking, prior: priorBlocking, shieldedCount: outcome.shieldedCount)
        syncStartingSoonNotifications(snapshots: snapshots)
    }

    /// Temporarily pauses the rule's current block: sets `pausedUntil` via
    /// `RulePolicy`, schedules the background re-arm, and refreshes so the
    /// shield clears. No-op (returns false) when the rule can't be paused.
    /// `pausedUntil` is set before the refresh, so the scheduler's reaping pass
    /// keeps the just-started re-arm.
    @discardableResult
    func pause(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) async -> Bool {
        guard RulePolicy.pause(
            rule, usage: usage(for: rule.dto, at: now, calendar: calendar),
            at: now, calendar: calendar)
        else { return false }
        if let pausedUntil = rule.pausedUntil {
            await engine.scheduleResumeReArm(for: rule.id, until: pausedUntil, now: now, calendar: calendar)
        }
        await refresh(rules: rules, at: now, calendar: calendar)
        return true
    }

    /// Ends a temporary pause now: clears `pausedUntil`, cancels the background
    /// re-arm, and refreshes so the shield re-engages.
    func resume(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) async {
        RulePolicy.resume(rule)
        await engine.cancelResumeReArm(for: rule.id)
        await refresh(rules: rules, at: now, calendar: calendar)
    }

    // MARK: - Main-actor model work

    /// Clears a pause that has elapsed so the rule re-arms once the pause lapses.
    private func expireStalePauseIfNeeded(_ rule: BlockingRule, at now: Date) {
        guard let pausedUntil = rule.pausedUntil, pausedUntil <= now else { return }
        rule.pausedUntil = nil
        let rid = rule.id.uuidString.prefix(8)
        Diag.log(.enforcer, "rule-\(rid): pause expired, re-armed")
    }

    /// 4c safety net: a skipped monitor `intervalDidStart` would block usage
    /// recording all day; establish today's confirmed start from the foreground
    /// (no zeroing — preserve any legitimate accrual).
    private func confirmForegroundDayStartIfNeeded(
        _ rule: BlockingRule, at now: Date, calendar: Calendar
    ) {
        guard rule.kind == .timeLimit, rule.isEnabled,
            dayStarts.confirmedStart(for: rule.id) != calendar.startOfDay(for: now)
        else { return }
        dayStarts.setConfirmedStart(calendar.startOfDay(for: now), for: rule.id)
        let rid = rule.id.uuidString.prefix(8)
        Diag.log(.dayStart, "rule-\(rid): foreground confirmed today's start (safety net)")
    }

    /// Publishes the new actively-blocking set and logs when it changes. "Blocked
    /// Apps" lists only rules whose budget/window is spent — not the proactive
    /// open-limit gate, which surfaces under "Usage" instead.
    private func commitBlockingSet(
        _ blocking: Set<UUID>, prior: Set<UUID>, shieldedCount: Int
    ) {
        blockingRuleIDs = blocking
        guard prior != blocking else { return }
        Diag.log(
            .enforcer, .event,
            "blocking set changed \(prior.count)->\(blocking.count); shielded=\(shieldedCount)")
    }

    /// Re-syncs the "starting soon" notifications off the same refresh funnel. The
    /// scheduler is an actor (overlapping fire-and-forget calls from the 30 s loop
    /// serialize) and fingerprint-gated, so this is cheap when unchanged.
    private func syncStartingSoonNotifications(snapshots: [RuleSnapshotDTO]) {
        guard let notificationScheduler else { return }
        let enabled = NotificationPreferences().scheduleStartEnabled
        Task { await notificationScheduler.sync(snapshots: snapshots, enabled: enabled) }
    }
}

/// The result of one off-main enforcement pass, handed back to the main actor.
nonisolated struct EnforcementOutcome: Sendable {
    let blocking: Set<UUID>
    let shieldedCount: Int
}

/// Performs the shield and DeviceActivity I/O that a `refresh` triggers, off the
/// main thread. Being an `actor` serializes overlapping refreshes so concurrent
/// triggers (a rule edit, the 30 s loop, a scenePhase change) can't race on
/// `DeviceActivityCenter` or the stored monitoring fingerprints. It speaks only
/// Sendable `RuleSnapshotDTO`s — never the SwiftData `@Model` — so nothing
/// main-actor-bound crosses the boundary. See `RuleEnforcer` for the split.
actor RuleEnforcementEngine {
    private let shields: any ShieldApplying
    private let scheduler: RuleScheduler?
    private let usageReader: any UsageReading
    private let openSessions: any OpenSessionReading

    init(
        shields: any ShieldApplying, scheduler: RuleScheduler?,
        usage: any UsageReading, openSessions: any OpenSessionReading
    ) {
        self.shields = shields
        self.scheduler = scheduler
        self.usageReader = usage
        self.openSessions = openSessions
    }

    /// Recomputes and applies shields from the given snapshots, reconciles
    /// DeviceActivity monitoring, and applies Uninstall Protection. Returns the
    /// blocking set for the caller to publish. Runs on the actor's executor —
    /// off the main thread.
    func apply(
        snapshots: [RuleSnapshotDTO], uninstallProtectionEnabled: Bool,
        at now: Date, calendar: Calendar
    ) -> EnforcementOutcome {
        var blocking: Set<UUID> = []
        var shielded: Set<UUID> = []
        for snapshot in snapshots {
            let outcome = evaluate(snapshot, at: now, calendar: calendar)
            if outcome.isBlocking { blocking.insert(snapshot.id) }
            if outcome.isShielded { shielded.insert(snapshot.id) }
        }
        shields.clearShields(except: shielded)
        shields.setAppRemovalDenied(
            RulePolicy.shouldDenyAppRemoval(
                snapshots: snapshots,
                enabled: uninstallProtectionEnabled,
                usageFor: { usage(for: $0, at: now, calendar: calendar) },
                at: now, calendar: calendar))
        scheduler?.sync(snapshots: snapshots, at: now, calendar: calendar)
        return EnforcementOutcome(blocking: blocking, shieldedCount: shielded.count)
    }

    /// Starts the background re-arm that re-engages a rule's shield when its
    /// temporary pause ends. Off-main so it never blocks the pause tap.
    func scheduleResumeReArm(for ruleID: UUID, until pausedUntil: Date, now: Date, calendar: Calendar) {
        scheduler?.scheduleResumeReArm(for: ruleID, until: pausedUntil, now: now, calendar: calendar)
    }

    /// Cancels a rule's pending pause re-arm (on resume).
    func cancelResumeReArm(for ruleID: UUID) {
        scheduler?.cancelResumeReArm(for: ruleID)
    }

    // MARK: - Per-rule evaluation (off main)

    /// The day's usage for a rule (nil for schedule rules, which don't track).
    private func usage(
        for snapshot: RuleSnapshotDTO, at now: Date, calendar: Calendar
    ) -> RuleUsageDTO? {
        guard snapshot.kind != .schedule else { return nil }
        return usageReader.usage(for: snapshot.id, onDayContaining: now, calendar: calendar)
    }

    /// Decides whether a rule is actively blocking and whether it should carry a
    /// shield (an active block, or an open-limit's proactive gate), applying the
    /// shield as a side effect. Returns both facts so `apply` can accumulate the
    /// blocking and shielded sets.
    private func evaluate(
        _ snapshot: RuleSnapshotDTO, at now: Date, calendar: Calendar
    ) -> (isBlocking: Bool, isShielded: Bool) {
        let usage = usage(for: snapshot, at: now, calendar: calendar)
        let status = snapshot.status(at: now, calendar: calendar, usage: usage)
        let isBlocking = status.isActive
        logTimeLimitDecision(snapshot, usage: usage, isBlocking: isBlocking, at: now)
        guard isBlocking || shouldGateOpenLimit(snapshot, at: now, calendar: calendar) else {
            let rid = snapshot.id.uuidString.prefix(8)
            Diag.log(
                .enforcer,
                "rule-\(rid) \(snapshot.kindRaw): not shielded (status=\(status) enabled=\(snapshot.isEnabled))")
            return (isBlocking, false)
        }
        applyShield(for: snapshot, status: status, usage: usage, isBlocking: isBlocking)
        return (isBlocking, true)
    }

    /// Surfaces the time-limit block decision: the threshold count vs the budget.
    private func logTimeLimitDecision(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO?, isBlocking: Bool, at now: Date
    ) {
        guard snapshot.kind == .timeLimit, let usage else { return }
        let rid = snapshot.id.uuidString.prefix(8)
        Diag.log(
            .usage,
            "timeLimit rule-\(rid) used=\(usage.minutesUsed)/\(snapshot.dailyLimitMinutes) blocking=\(isBlocking)")
    }

    /// Records the rule's shield and writes it. Allow Only is a Schedule-only
    /// option; the model already forces `.block` on limit rules, so we forward
    /// the rule's values directly.
    private func applyShield(
        for snapshot: RuleSnapshotDTO, status: RuleStatus, usage: RuleUsageDTO?, isBlocking: Bool
    ) {
        let rid = snapshot.id.uuidString.prefix(8)
        Diag.log(
            .enforcer, .event,
            "rule-\(rid) \(snapshot.kindRaw): shield (\(isBlocking ? "active status=\(status)" : "open-limit gate")\(usage.map { ", used=\($0.minutesUsed)/opens=\($0.opensUsed)" } ?? ""))")
        shields.applyShield(
            ruleID: snapshot.id,
            selectionData: snapshot.selectionData,
            mode: snapshot.selectionMode
        )
    }

    /// Whether an open-limit rule should carry its proactive gate right now:
    /// enabled, scheduled today, not paused, and not inside a granted open
    /// session (which would otherwise be cut short). Mirrors
    /// `LimitEnforcement.handleDayStart` so the foreground and background agree.
    private func shouldGateOpenLimit(
        _ snapshot: RuleSnapshotDTO, at now: Date, calendar: Calendar
    ) -> Bool {
        snapshot.kind == .openLimit
            && snapshot.isEnabled
            && snapshot.pausedUntil == nil
            && snapshot.isScheduledToday(at: now, calendar: calendar)
            && !openSessions.hasActiveSession(for: snapshot.id, at: now)
    }
}
