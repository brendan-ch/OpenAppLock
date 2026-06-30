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
@Observable
final class RuleEnforcer {
    private(set) var blockingRuleIDs: Set<UUID> = []
    private let shields: ShieldApplying
    /// Mirrors rules to the app group and keeps DeviceActivity monitoring in
    /// step; nil in UI-test launches.
    private let scheduler: RuleScheduler?
    /// Keeps the pre-scheduled "a schedule rule starts in 5 minutes"
    /// notifications in step with the rules; nil in UI-test launches (and when
    /// the feature isn't wired). Driven off the same refresh funnel.
    private let notificationScheduler: NotificationScheduler?
    /// Day-usage source consulted for limit rules; also exposed to views for
    /// the Usage section.
    let usageReader: UsageReading
    /// Granted-open sessions, so a proactively-gated open-limit rule is left
    /// un-shielded while the user is inside a session they paid an open for.
    private let openSessions: OpenSessionReading
    /// App-wide settings (currently just Uninstall Protection) consulted on
    /// every refresh.
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
        self.shields = shields
        self.usageReader = usage
        self.scheduler = scheduler
        self.notificationScheduler = notificationScheduler
        self.openSessions = openSessions
        self.settings = settings
        self.dayStarts = dayStarts
    }

    /// The day's usage for a rule (nil for schedule rules, which don't track).
    func usage(
        for snapshot: RuleSnapshotDTO, at now: Date = .now, calendar: Calendar = .current
    ) -> RuleUsageDTO? {
        guard snapshot.kind != .schedule else { return nil }
        return usageReader.usage(for: snapshot.id, onDayContaining: now, calendar: calendar)
    }

    /// Recomputes shields from scratch. Call on launch, on any rule change,
    /// and periodically while the app is visible. Also expires stale pauses.
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
    func refresh(rules: [BlockingRule], at now: Date = .now, calendar: Calendar = .current) {
        let priorBlocking = blockingRuleIDs
        Diag.log(.enforcer, "refresh: \(rules.count) rules at \(LogTimestamp.string(from: now))")
        var blocking: Set<UUID> = []
        var shielded: Set<UUID> = []
        for rule in rules {
            let outcome = evaluate(rule, at: now, calendar: calendar)
            if outcome.isBlocking { blocking.insert(rule.id) }
            if outcome.isShielded { shielded.insert(rule.id) }
        }
        shields.clearShields(except: shielded)
        commitBlockingSet(blocking, prior: priorBlocking, shieldedCount: shielded.count)
        applyUninstallProtection(rules: rules, at: now, calendar: calendar)
        scheduler?.sync(rules: rules, at: now, calendar: calendar)
        syncStartingSoonNotifications(rules: rules)
    }

    /// Temporarily pauses the rule's current block: sets `pausedUntil` via
    /// `RulePolicy`, schedules the background re-arm, and refreshes so the
    /// shield clears immediately. No-op (returns false) when the rule can't be
    /// paused. `pausedUntil` is set before the refresh, so the scheduler's
    /// reaping pass keeps the just-started re-arm.
    @discardableResult
    func pause(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard RulePolicy.pause(
            rule, usage: usage(for: rule.dto, at: now, calendar: calendar),
            at: now, calendar: calendar)
        else { return false }
        if let pausedUntil = rule.pausedUntil {
            scheduler?.scheduleResumeReArm(for: rule.id, until: pausedUntil, now: now, calendar: calendar)
        }
        refresh(rules: rules, at: now, calendar: calendar)
        return true
    }

    /// Ends a temporary pause now: clears `pausedUntil`, cancels the background
    /// re-arm, and refreshes so the shield re-engages immediately.
    func resume(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) {
        RulePolicy.resume(rule)
        scheduler?.cancelResumeReArm(for: rule.id)
        refresh(rules: rules, at: now, calendar: calendar)
    }

    /// Runs one rule through the refresh pipeline — expire a stale pause, confirm
    /// today's day-start, then decide whether it is actively blocking and whether
    /// it should carry a shield (an active block, or an open-limit's proactive
    /// gate), applying the shield as a side effect. Returns both facts so
    /// `refresh` can accumulate the blocking and shielded sets.
    private func evaluate(
        _ rule: BlockingRule, at now: Date, calendar: Calendar
    ) -> (isBlocking: Bool, isShielded: Bool) {
        expireStalePauseIfNeeded(rule, at: now)
        confirmForegroundDayStartIfNeeded(rule, at: now, calendar: calendar)
        let snapshot = rule.dto
        let usage = usage(for: snapshot, at: now, calendar: calendar)
        let status = snapshot.status(at: now, calendar: calendar, usage: usage)
        let isBlocking = status.isActive
        logTimeLimitDecision(rule, usage: usage, isBlocking: isBlocking, at: now)
        guard isBlocking || shouldGateOpenLimit(snapshot, at: now, calendar: calendar) else {
            let rid = rule.id.uuidString.prefix(8)
            Diag.log(
                .enforcer,
                "rule-\(rid) \(rule.kindRaw): not shielded (status=\(status) enabled=\(rule.isEnabled))")
            return (isBlocking, false)
        }
        applyShield(for: snapshot, status: status, usage: usage, isBlocking: isBlocking)
        return (isBlocking, true)
    }

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

    /// Surfaces the time-limit block decision: the threshold count vs the budget.
    private func logTimeLimitDecision(
        _ rule: BlockingRule, usage: RuleUsageDTO?, isBlocking: Bool, at now: Date
    ) {
        guard rule.kind == .timeLimit, let usage else { return }
        let rid = rule.id.uuidString.prefix(8)
        Diag.log(
            .usage,
            "timeLimit rule-\(rid) used=\(usage.minutesUsed)/\(rule.dailyLimitMinutes) blocking=\(isBlocking)")
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

    /// Uninstall Protection: deny device app removal while the user has opted in
    /// and any Hard Mode rule is actively blocking.
    private func applyUninstallProtection(
        rules: [BlockingRule], at now: Date, calendar: Calendar
    ) {
        shields.setAppRemovalDenied(
            RulePolicy.shouldDenyAppRemoval(
                snapshots: rules.map(\.dto),
                enabled: settings.uninstallProtectionEnabled,
                usageFor: { usage(for: $0, at: now, calendar: calendar) },
                at: now, calendar: calendar))
    }

    /// Re-syncs the "starting soon" notifications off the same refresh funnel. The
    /// scheduler is an actor (overlapping fire-and-forget calls from the 30 s loop
    /// serialize) and fingerprint-gated, so this is cheap when unchanged.
    private func syncStartingSoonNotifications(rules: [BlockingRule]) {
        guard let notificationScheduler else { return }
        let snapshots = rules.map(\.dto)
        let enabled = NotificationPreferences().scheduleStartEnabled
        Task { await notificationScheduler.sync(snapshots: snapshots, enabled: enabled) }
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
