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
        for rule: BlockingRule, at now: Date = .now, calendar: Calendar = .current
    ) -> RuleUsage? {
        guard rule.kind != .schedule else { return nil }
        return usageReader.usage(for: rule.id, onDayContaining: now, calendar: calendar)
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
    /// through another rule's block (see `ShieldController`); and a soft unblock
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
            let rid = rule.id.uuidString.prefix(8)
            if let pausedUntil = rule.pausedUntil, pausedUntil <= now {
                rule.pausedUntil = nil
                Diag.log(.enforcer, "rule-\(rid): pause expired, re-armed")
            }
            // 4c safety net: a skipped monitor `intervalDidStart` would block
            // usage recording all day; establish today's confirmed start from the
            // foreground (no zeroing — preserve any legitimate accrual).
            if rule.kind == .timeLimit, rule.isEnabled,
               dayStarts.confirmedStart(for: rule.id) != calendar.startOfDay(for: now) {
                dayStarts.setConfirmedStart(calendar.startOfDay(for: now), for: rule.id)
                Diag.log(.dayStart, "rule-\(rid): foreground confirmed today's start (safety net)")
            }
            let usage = usage(for: rule, at: now, calendar: calendar)
            let status = rule.status(at: now, calendar: calendar, usage: usage)
            let isBlocking = status.isActive
            if isBlocking { blocking.insert(rule.id) }
            // EC4/EC9: surface the authoritative-vs-threshold decision for time
            // limits — which source the block decision used, its freshness, and a
            // WARN when the report's (app-token-only) authoritative figure has
            // lifted a block the threshold count says is real.
            if rule.kind == .timeLimit, let usage {
                let limit = rule.dailyLimitMinutes
                let effective = usage.effectiveMinutesUsed(asOf: now)
                let asOfAge = usage.authoritativeAsOf.map { Int(now.timeIntervalSince($0)) }
                let usingAuthoritative =
                    usage.authoritativeMinutesUsed != nil
                    && (asOfAge.map { abs($0) <= Int(RuleUsage.authoritativeFreshness) } ?? false)
                Diag.log(
                    .usage,
                    "timeLimit rule-\(rid) threshold=\(usage.minutesUsed) auth=\(usage.authoritativeMinutesUsed.map(String.init) ?? "-")@\(asOfAge.map { "\($0)s" } ?? "-") effective=\(effective)/\(limit) source=\(usingAuthoritative ? "authoritative" : "threshold")")
                if !isBlocking, usage.minutesUsed >= limit, effective < limit {
                    Diag.log(
                        .usage, .error,
                        "WARN rule-\(rid): authoritative lifted a real block (threshold=\(usage.minutesUsed)>=\(limit) but effective=\(effective)) — possible category/web undercount (EC4)")
                }
            }
            let gating = !isBlocking && shouldGateOpenLimit(rule, at: now, calendar: calendar)
            guard isBlocking || gating else {
                Diag.log(
                    .enforcer,
                    "rule-\(rid) \(rule.kindRaw): not shielded (status=\(status) enabled=\(rule.isEnabled))")
                continue
            }
            shielded.insert(rule.id)
            Diag.log(
                .enforcer, .event,
                "rule-\(rid) \(rule.kindRaw): shield (\(isBlocking ? "active status=\(status)" : "open-limit gate")\(usage.map { ", used=\($0.minutesUsed)/opens=\($0.opensUsed)" } ?? ""))")
            shields.applyShield(
                ruleID: rule.id,
                selectionData: rule.appList?.selectionData,
                // Allow Only and Block Adult Content are Schedule-only options;
                // the model already forces .block / false on limit rules, so we
                // can forward the rule's values directly.
                mode: rule.selectionMode,
                blockAdultContent: rule.blockAdultContent
            )
        }
        shields.clearShields(except: shielded)
        // "Blocked Apps" lists only rules whose budget/window is spent — not the
        // proactive open-limit gate, which surfaces under "Usage" instead.
        blockingRuleIDs = blocking
        if priorBlocking != blocking {
            Diag.log(
                .enforcer, .event,
                "blocking set changed \(priorBlocking.count)->\(blocking.count); shielded=\(shielded.count)")
        }
        // Uninstall Protection: deny device app removal while the user has opted
        // in and any Hard Mode rule is actively blocking.
        shields.setAppRemovalDenied(
            RulePolicy.shouldDenyAppRemoval(
                rules: rules,
                enabled: settings.uninstallProtectionEnabled,
                usageFor: { usage(for: $0, at: now, calendar: calendar) },
                at: now, calendar: calendar))
        scheduler?.sync(rules: rules, at: now)
        // Re-sync the "starting soon" notifications off the same funnel. The
        // scheduler is an actor (overlapping fire-and-forget calls from the 30 s
        // loop serialize) and fingerprint-gated, so this is cheap when unchanged.
        if let notificationScheduler {
            let snapshots = rules.map(RuleSnapshot.init)
            let enabled = NotificationPreferences().scheduleStartEnabled
            Task { await notificationScheduler.sync(snapshots: snapshots, enabled: enabled) }
        }
    }

    /// Whether an open-limit rule should carry its proactive gate right now:
    /// enabled, scheduled today, not unblocked, and not inside a granted open
    /// session (which would otherwise be cut short). Mirrors
    /// `LimitEnforcement.handleDayStart` so the foreground and background agree.
    private func shouldGateOpenLimit(
        _ rule: BlockingRule, at now: Date, calendar: Calendar
    ) -> Bool {
        rule.kind == .openLimit
            && rule.isEnabled
            && rule.pausedUntil == nil
            && rule.isScheduledToday(at: now, calendar: calendar)
            && !openSessions.hasActiveSession(for: rule.id, at: now)
    }
}
