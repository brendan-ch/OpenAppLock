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

    /// Wall-clock length of one granted open. 15 minutes is DeviceActivity's
    /// minimum schedule interval, so an "open" lasts at most this long before
    /// the shield returns.
    static let openSessionMinutes = 15

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

    /// Cumulative-usage checkpoints for a time-limit rule: one event per
    /// minute up to the budget so remaining time can be displayed live; the
    /// final one doubles as the block trigger. (Budgets cap at 240 minutes,
    /// comfortably inside DeviceActivity's event capacity.)
    static func minuteEvents(forLimit limitMinutes: Int) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: (1...max(1, limitMinutes)).map {
                (minuteEventName(for: $0), $0)
            }
        )
    }
}
