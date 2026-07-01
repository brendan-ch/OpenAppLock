//
//  LimitWarningDecision.swift
//  OpenAppLock
//

import Foundation

/// Pure decision for the "your time limit has ~5 minutes left" notification,
/// shared so the monitor extension (which posts it when a warn event fires) and
/// the unit tests agree on eligibility. No `UserNotifications` import, so it is
/// safe in `Shared/` across every target.
enum LimitWarningDecision {
    /// The content to post, or nil when this rule should not warn right now.
    ///
    /// Eligible only when the time-limit notification is on (toggle AND
    /// authorization, via ``NotificationPreferences``), the rule is an enabled
    /// time limit that is scheduled today and not paused, and its budget is
    /// not already spent (a late/stale warn after the block already fired must
    /// not nag).
    static func content(
        for snapshot: RuleSnapshotDTO?,
        usage: RuleUsageDTO,
        preferences: NotificationPreferences,
        activityDayKey: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (title: String, body: String)? {
        // A warn event tagged with a prior day key is a cross-midnight stale
        // flush from yesterday's per-day warn activity; drop it so it can't post
        // a spurious "5 minutes left" notification on a fresh day. Nil (a legacy
        // un-keyed activity) skips the check.
        if let activityDayKey, activityDayKey != UsageLedger.dayKey(for: now, calendar: calendar) {
            return nil
        }
        guard preferences.timeLimitEndingEnabled,
              let snapshot,
              snapshot.isEnabled,
              snapshot.kind == .timeLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar),
              !snapshot.limitReached(given: usage, at: now)
        else { return nil }

        return (
            title: CopyKey.notificationTimeLimitWarningTitle.string,
            body: CopyKey.notificationTimeLimitWarningBodyFormat.string(
                snapshot.name, MonitoringPlan.limitWarningLeadMinutes)
        )
    }
}
