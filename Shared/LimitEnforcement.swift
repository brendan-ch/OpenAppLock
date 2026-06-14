//
//  LimitEnforcement.swift
//  OpenAppLock
//

import Foundation

/// Shared reactions to Screen Time events for limit rules, driven by the
/// snapshot store and usage ledger. The DeviceActivity monitor and shield
/// extensions call these; keeping the logic here makes it unit-testable from
/// the app target.
struct LimitEnforcement {
    let snapshots: RuleSnapshotStore
    let ledger: UsageLedger
    let shields: ShieldApplying
    /// Granted-open session bookkeeping shared with the foreground enforcer.
    var sessions = OpenSessionStore()

    /// Midnight (or monitoring start): fresh budgets. Open-limit rules are
    /// proactively shielded on enabled days so the shield can count opens;
    /// time-limit rules start the day unshielded.
    func handleDayStart(ruleID: UUID, now: Date = .now, calendar: Calendar = .current) {
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              !snapshot.isPaused(at: now)
        else { return }
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        switch snapshot.kind {
        case .schedule:
            break
        case .openLimit:
            if snapshot.isScheduledToday(at: now, calendar: calendar) {
                shield(snapshot)
            } else {
                shields.clearShield(ruleID: ruleID)
            }
        case .timeLimit:
            if snapshot.limitReached(given: usage),
               snapshot.isScheduledToday(at: now, calendar: calendar) {
                shield(snapshot)
            } else {
                shields.clearShield(ruleID: ruleID)
            }
        }
    }

    /// A cumulative usage checkpoint fired for a time-limit rule.
    func handleUsageMinutes(
        _ minutes: Int, ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) {
        ledger.recordMinutesUsed(minutes, for: ruleID, onDayContaining: now, calendar: calendar)
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .timeLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar)
        else { return }
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        if snapshot.limitReached(given: usage) {
            shield(snapshot)
        }
    }

    /// The wall-clock session granted by an "Open" press ended; the shield
    /// returns so the next open costs another press.
    func handleOpenSessionEnded(
        ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) {
        sessions.endSession(for: ruleID)
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .openLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar)
        else { return }
        shield(snapshot)
    }

    /// "Open" pressed on the shield. Spends one open and lifts the rule's
    /// shield when the budget allows; returns whether a session was granted.
    @discardableResult
    func handleOpenRequest(
        ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .openLimit,
              !snapshot.isPaused(at: now)
        else { return false }
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        guard !snapshot.limitReached(given: usage) else { return false }
        ledger.recordOpen(for: ruleID, onDayContaining: now, calendar: calendar)
        shields.clearShield(ruleID: ruleID)
        // Mark the session so neither enforcement path re-shields the app until
        // it ends (+1 minute matches the one-shot activity's padding).
        if let expiry = calendar.date(
            byAdding: .minute, value: MonitoringPlan.openSessionMinutes + 1, to: now)
        {
            sessions.startSession(for: ruleID, until: expiry)
        }
        return true
    }

    private func shield(_ snapshot: RuleSnapshot) {
        shields.applyShield(
            ruleID: snapshot.id,
            selectionData: snapshot.selectionData,
            // Limit rules are always Block and never engage the adult-content
            // filter — those are Schedule-only options.
            mode: .block,
            blockAdultContent: false
        )
    }
}
