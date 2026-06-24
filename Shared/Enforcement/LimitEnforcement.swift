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
        let rid = ruleID.uuidString.prefix(8)
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              !snapshot.isPaused(at: now)
        else {
            Diag.log(.dayStart, "dayStart rule-\(rid): skipped (missing/disabled/paused)")
            return
        }
        confirmDayStart(ruleID: ruleID, kind: snapshot.kind, now: now, calendar: calendar)
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        let scheduledToday = snapshot.isScheduledToday(at: now, calendar: calendar)
        switch snapshot.kind {
        case .schedule:
            break
        case .openLimit:
            if scheduledToday {
                Diag.log(.dayStart, .event, "dayStart rule-\(rid) openLimit: shield (proactive gate, scheduled today)")
                shield(snapshot)
            } else {
                Diag.log(.dayStart, "dayStart rule-\(rid) openLimit: clear (not scheduled today)")
                shields.clearShield(ruleID: ruleID)
            }
        case .timeLimit:
            if snapshot.limitReached(given: usage, at: now), scheduledToday {
                Diag.log(.dayStart, .event, "dayStart rule-\(rid) timeLimit: shield (limit already reached, used=\(usage.minutesUsed)/\(snapshot.dailyLimitMinutes))")
                shield(snapshot)
            } else {
                Diag.log(.dayStart, "dayStart rule-\(rid) timeLimit: clear (used=\(usage.minutesUsed)/\(snapshot.dailyLimitMinutes) scheduledToday=\(scheduledToday))")
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
        guard dayStarts.confirmedStart(for: ruleID) != today else {
            // EC6: a same-day re-fire must NOT zero today's accrual; log that it
            // was correctly skipped (vs the new-day zero below).
            Diag.log(
                .dayStart,
                "confirm rule-\(ruleID.uuidString.prefix(8)): skipped (same-day re-fire, start already \(LogTimestamp.string(from: today)))")
            return
        }
        dayStarts.setConfirmedStart(today, for: ruleID)
        Diag.log(
            .dayStart, .event,
            "confirm rule-\(ruleID.uuidString.prefix(8)) start=\(LogTimestamp.string(from: today))"
                + (kind == .timeLimit ? " (zeroed today's ledger)" : ""))
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
        let rid = ruleID.uuidString.prefix(8)
        let minutesSinceMidnight = Int(
            now.timeIntervalSince(calendar.startOfDay(for: now)) / 60)
        Diag.log(
            .usage, .event,
            "usageEvent rule-\(rid) minutes=\(minutes) sinceMidnight=\(minutesSinceMidnight)")
        guard minutes <= minutesSinceMidnight else {
            Diag.log(
                .usage,
                "drop rule-\(rid): stale checkpoint minutes=\(minutes) > sinceMidnight=\(minutesSinceMidnight) (late cross-midnight flush)")
            return
        }
        // Reject events that arrive before today's interval boundary has been
        // observed — yesterday's batched checkpoints flushed late across midnight.
        guard dayStarts.hasConfirmedStart(for: ruleID, onDayContaining: now, calendar: calendar)
        else {
            Diag.log(.usage, "drop rule-\(rid): no confirmed day-start yet (pre-boundary flush)")
            return
        }

        // Record only for a rule that can actually be active today, so a stale or
        // irrelevant event can't corrupt today's ledger for a rule that isn't.
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .timeLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar)
        else {
            Diag.log(
                .usage,
                "drop rule-\(rid): not eligible today (enabled/timeLimit/unpaused/scheduledToday check failed)")
            return
        }
        ledger.recordMinutesUsed(minutes, for: ruleID, onDayContaining: now, calendar: calendar)
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        let reached = snapshot.limitReached(given: usage, at: now)
        Diag.log(
            .usage, .event,
            "record rule-\(rid) used=\(usage.minutesUsed)/\(snapshot.dailyLimitMinutes) limitReached=\(reached)")
        if reached {
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
        else {
            Diag.log(
                .session,
                "openSessionEnded rule-\(ruleID.uuidString.prefix(8)): no re-shield (ineligible)")
            return
        }
        Diag.log(.session, .event, "openSessionEnded rule-\(ruleID.uuidString.prefix(8)): re-shield")
        shield(snapshot)
    }

    /// "Open" pressed on the shield. Spends one open and lifts the rule's
    /// shield when the budget allows; returns whether a session was granted.
    @discardableResult
    func handleOpenRequest(
        ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        let rid = ruleID.uuidString.prefix(8)
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .openLimit,
              !snapshot.isPaused(at: now)
        else {
            Diag.log(.session, "openRequest rule-\(rid): denied (ineligible)")
            return false
        }
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        guard !snapshot.limitReached(given: usage, at: now) else {
            Diag.log(
                .session, .event,
                "openRequest rule-\(rid): denied (opens spent \(usage.opensUsed)/\(snapshot.maxOpens))")
            return false
        }
        let updated = ledger.recordOpen(for: ruleID, onDayContaining: now, calendar: calendar)
        shields.clearShield(ruleID: ruleID)
        // Mark the session so neither enforcement path re-shields the app until
        // it ends (+1 minute matches the one-shot activity's padding).
        if let expiry = calendar.date(
            byAdding: .minute, value: MonitoringPlan.openSessionMinutes + 1, to: now)
        {
            sessions.startSession(for: ruleID, until: expiry)
        }
        Diag.log(
            .session, .event,
            "openRequest rule-\(rid): granted (open \(updated.opensUsed)/\(snapshot.maxOpens), ~\(MonitoringPlan.openSessionMinutes)m session)")
        return true
    }

    private func shield(_ snapshot: RuleSnapshotDTO) {
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
