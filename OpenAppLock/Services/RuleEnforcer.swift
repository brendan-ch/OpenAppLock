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
    /// Day-usage source consulted for limit rules; also exposed to views for
    /// the Usage section.
    let usageReader: UsageReading
    /// Granted-open sessions, so a proactively-gated open-limit rule is left
    /// un-shielded while the user is inside a session they paid an open for.
    private let openSessions: OpenSessionReading
    /// App-wide settings (currently just Uninstall Protection) consulted on
    /// every refresh.
    private let settings: any AppSettingsReading

    init(
        shields: ShieldApplying, usage: UsageReading = UsageLedger(),
        scheduler: RuleScheduler? = nil,
        openSessions: OpenSessionReading = OpenSessionStore(),
        settings: any AppSettingsReading = AppSettingsStore()
    ) {
        self.shields = shields
        self.usageReader = usage
        self.scheduler = scheduler
        self.openSessions = openSessions
        self.settings = settings
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
        var blocking: Set<UUID> = []
        var shielded: Set<UUID> = []
        for rule in rules {
            if let pausedUntil = rule.pausedUntil, pausedUntil <= now {
                rule.pausedUntil = nil
            }
            let usage = usage(for: rule, at: now, calendar: calendar)
            let isBlocking = rule.status(at: now, calendar: calendar, usage: usage).isActive
            if isBlocking { blocking.insert(rule.id) }
            guard isBlocking || shouldGateOpenLimit(rule, at: now, calendar: calendar) else {
                continue
            }
            shielded.insert(rule.id)
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
        // Uninstall Protection: deny device app removal while the user has opted
        // in and any Hard Mode rule is actively blocking.
        shields.setAppRemovalDenied(
            RulePolicy.shouldDenyAppRemoval(
                rules: rules,
                enabled: settings.uninstallProtectionEnabled,
                usageFor: { usage(for: $0, at: now, calendar: calendar) },
                at: now, calendar: calendar))
        scheduler?.sync(rules: rules, at: now)
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
