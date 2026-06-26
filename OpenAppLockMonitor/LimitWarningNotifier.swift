//
//  LimitWarningNotifier.swift
//  OpenAppLockMonitor
//

import Foundation
import UserNotifications

/// Posts the "your time limit has ~5 minutes left" notification when the
/// dedicated warn activity's threshold event fires. The eligibility/content
/// decision lives in the pure, shared `LimitWarningDecision`; this is the thin
/// shell that gathers the snapshot + usage and hands off to the system. Lives in
/// the monitor target (not `Shared/`) so `UserNotifications` doesn't leak into
/// the other extensions.
struct LimitWarningNotifier {
    var snapshots = RuleSnapshotUserDefaultsStore()
    var ledger = UsageLedger()
    var preferences = NotificationPreferences()
    var center: UNUserNotificationCenter = .current()

    func notifyIfEligible(ruleID: UUID, now: Date = .now, calendar: Calendar = .current) {
        let snapshot = snapshots.snapshot(for: ruleID)
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        guard
            let content = LimitWarningDecision.content(
                for: snapshot, usage: usage, preferences: preferences,
                now: now, calendar: calendar)
        else { return }

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        // A nil trigger delivers immediately.
        center.add(
            UNNotificationRequest(
                identifier: "time-limit-warning-\(ruleID.uuidString)",
                content: notification, trigger: nil))
    }
}
