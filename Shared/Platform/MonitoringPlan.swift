//
//  MonitoringPlan.swift
//  OpenAppLock
//

import Foundation

/// Naming conventions and event layouts shared by the app (which starts
/// DeviceActivity monitoring) and the monitor extension (which decodes what
/// fired).
enum MonitoringPlan {
    private static let dailyPrefix = "rule-"
    private static let sessionPrefix = "open-session-"
    private static let minutePrefix = "minutes-"
    private static let scheduleWindowPrefix = "sched-"
    private static let scheduleWindowLatePrefix = "sched2-"
    private static let warnActivityPrefix = "tlwarn-"
    private static let warnEventPrefix = "warn-"
    private static let pausePrefix = "pause-"

    /// How early the "time limit almost up" notification fires, in minutes of
    /// remaining allowance.
    static let limitWarningLeadMinutes = 5

    /// Wall-clock length of one granted open. 15 minutes is DeviceActivity's
    /// minimum schedule interval, so an "open" lasts at most this long before
    /// the shield returns.
    static let openSessionMinutes = 15

    /// Wall-clock length of a temporary pause. 15 minutes is DeviceActivity's
    /// minimum schedule interval, so the one-shot re-arm that re-engages the
    /// shield can fire right at the pause's end (with one extra minute of
    /// interval padding, as for granted opens).
    static let temporaryPauseMinutes = 15

    /// The always-on, midnight-to-midnight activity tracking a rule's day.
    static func dailyActivityName(for ruleID: UUID) -> String {
        dailyPrefix + ruleID.uuidString
    }

    /// The one-shot activity timing a granted open.
    static func sessionActivityName(for ruleID: UUID) -> String {
        sessionPrefix + ruleID.uuidString
    }

    static func ruleID(fromDailyActivityName name: String) -> UUID? {
        guard name.hasPrefix(dailyPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(dailyPrefix.count)))
    }

    static func ruleID(fromSessionActivityName name: String) -> UUID? {
        guard name.hasPrefix(sessionPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(sessionPrefix.count)))
    }

    /// The one-shot activity that re-engages a rule's shield when its temporary
    /// pause ends. A distinct prefix means no other parser misclassifies it.
    static func pauseActivityName(for ruleID: UUID) -> String {
        pausePrefix + ruleID.uuidString
    }

    static func ruleID(fromPauseActivityName name: String) -> UUID? {
        guard name.hasPrefix(pausePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(pausePrefix.count)))
    }

    /// The primary window activity for a schedule rule. A second
    /// (`scheduleWindowLateName`) covers the post-midnight half of a window
    /// that crosses midnight, since DeviceActivity can't express an interval
    /// whose end is earlier than its start.
    static func scheduleWindowName(for ruleID: UUID) -> String {
        scheduleWindowPrefix + ruleID.uuidString
    }

    static func scheduleWindowLateName(for ruleID: UUID) -> String {
        scheduleWindowLatePrefix + ruleID.uuidString
    }

    static func ruleID(fromScheduleWindowName name: String) -> UUID? {
        if name.hasPrefix(scheduleWindowLatePrefix) {
            return UUID(uuidString: String(name.dropFirst(scheduleWindowLatePrefix.count)))
        }
        if name.hasPrefix(scheduleWindowPrefix) {
            return UUID(uuidString: String(name.dropFirst(scheduleWindowPrefix.count)))
        }
        return nil
    }

    static func minuteEventName(for minutes: Int) -> String {
        minutePrefix + String(minutes)
    }

    static func minutes(fromEventName name: String) -> Int? {
        guard name.hasPrefix(minutePrefix) else { return nil }
        return Int(name.dropFirst(minutePrefix.count))
    }

    /// The single cumulative-usage checkpoint for a time-limit rule: one event
    /// at the budget, used by the monitor as the background block trigger. Live
    /// sub-budget progress comes from the DeviceActivityReport extension, not a
    /// per-minute chain (Screen Time batches sub-budget thresholds unreliably).
    static func blockEvent(forLimit limitMinutes: Int) -> [String: Int] {
        let minutes = max(1, limitMinutes)
        return [minuteEventName(for: minutes): minutes]
    }

    /// The dedicated, opt-in "time limit almost up" activity for a rule, kept
    /// separate from the rule's enforcement (`dailyActivityName`) activity so
    /// toggling the notification never restarts — and so never resets the usage
    /// threshold accounting of — the activity that actually blocks. A distinct
    /// prefix means `ruleID(fromDailyActivityName:)` never mistakes it for the
    /// enforcement activity.
    static func warnActivityName(for ruleID: UUID) -> String {
        warnActivityPrefix + ruleID.uuidString
    }

    static func ruleID(fromWarnActivityName name: String) -> UUID? {
        guard name.hasPrefix(warnActivityPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(warnActivityPrefix.count)))
    }

    /// The single threshold event for the warn activity: one checkpoint
    /// `limitWarningLeadMinutes` before the budget. Returns nil when the budget
    /// is at or below the lead time (no meaningful "5 minutes left" moment).
    static func warnEvent(forLimit limitMinutes: Int) -> [String: Int]? {
        let threshold = limitMinutes - limitWarningLeadMinutes
        guard threshold >= 1 else { return nil }
        return [warnEventPrefix + String(threshold): threshold]
    }
}
