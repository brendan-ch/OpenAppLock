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
    /// Confirmed daily-activity starts, used to reject pre-boundary stale flushes.
    var dayStarts = DayStartStore()

    /// Midnight (or monitoring start): fresh budgets. Open-limit rules are
    /// proactively shielded on enabled days so the shield can count opens;
    /// time-limit rules start the day unshielded.
    func handleDayStart(ruleID: UUID, now: Date = .now, calendar: Calendar = .current) {
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              !snapshot.isPaused(at: now)
        else { return }
        confirmDayStart(ruleID: ruleID, kind: snapshot.kind, now: now, calendar: calendar)
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

    /// Records today as the confirmed interval start for `ruleID`. On a genuine
    /// new-day transition for a time-limit rule, zeroes today's ledger once so a
    /// stale pre-boundary checkpoint cannot survive; a spurious same-day re-fire
    /// must not erase legitimate usage.
    private func confirmDayStart(
        ruleID: UUID, kind: RuleKind, now: Date, calendar: Calendar
    ) {
        let today = calendar.startOfDay(for: now)
        guard dayStarts.confirmedStart(for: ruleID) != today else { return }
        dayStarts.setConfirmedStart(today, for: ruleID)
        if kind == .timeLimit {
            ledger.setUsage(RuleUsage(), for: ruleID, onDayContaining: now, calendar: calendar)
        }
    }

    /// A cumulative usage checkpoint fired for a time-limit rule.
    func handleUsageMinutes(
        _ minutes: Int, ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) {
        // A `minutes-k` checkpoint reports k minutes of *today's* usage, which
        // cannot have accrued before k minutes have elapsed since local
        // midnight. A larger value means the callback is stale — typically
        // yesterday's spent budget delivered late across midnight, since Screen
        // Time batches threshold events and fires them when it next wakes the
        // monitor (e.g. as another rule's window opens). Recording it would
        // re-block apps the user never opened today, so drop it.
        let minutesSinceMidnight = Int(
            now.timeIntervalSince(calendar.startOfDay(for: now)) / 60)
        guard minutes <= minutesSinceMidnight else { return }
        // Reject events that arrive before today's interval boundary has been
        // observed — yesterday's batched checkpoints flushed late across midnight.
        guard dayStarts.hasConfirmedStart(for: ruleID, onDayContaining: now, calendar: calendar)
        else { return }

        // Record only for a rule that can actually be active today, so a stale or
        // irrelevant event can't corrupt today's ledger for a rule that isn't.
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .timeLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar)
        else { return }
        ledger.recordMinutesUsed(minutes, for: ruleID, onDayContaining: now, calendar: calendar)
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
