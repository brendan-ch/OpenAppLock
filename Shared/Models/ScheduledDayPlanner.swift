//
//  ScheduledDayPlanner.swift
//  OpenAppLock
//

import Foundation

/// Pure day-granularity scheduling helpers shared by the foreground scheduler
/// (which arms the next N scheduled per-day activities) and the background
/// monitor (which self-arms the next scheduled day when one ends). Weekday
/// membership only — windows/usage live elsewhere.
nonisolated enum ScheduledDayPlanner {
    private static let searchHorizonDays = 14

    /// Up to `count` `startOfDay` Dates, beginning at the day containing `now`,
    /// on which `days` schedules the rule. Empty when `days` is empty.
    static func upcomingScheduledDayStarts(
        days: Set<Weekday>, from now: Date, count: Int, calendar: Calendar = .current
    ) -> [Date] {
        guard !days.isEmpty, count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [Date] = []
        var offset = 0
        while result.count < count, offset < searchHorizonDays {
            if let day = calendar.date(byAdding: .day, value: offset, to: today),
               let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
               days.contains(weekday) {
                result.append(day)
            }
            offset += 1
        }
        return result
    }

    /// The `startOfDay` of the first scheduled day strictly after the day
    /// containing `day`, or nil when none falls inside the search horizon.
    static func nextScheduledDayStart(
        after day: Date, days: Set<Weekday>, calendar: Calendar = .current
    ) -> Date? {
        guard !days.isEmpty else { return nil }
        let base = calendar.startOfDay(for: day)
        for offset in 1...searchHorizonDays {
            if let candidate = calendar.date(byAdding: .day, value: offset, to: base),
               let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)),
               days.contains(weekday) {
                return candidate
            }
        }
        return nil
    }
}
