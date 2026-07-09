//
//  RuleSchedule.swift
//  OpenAppLock
//

import Foundation

/// The recurring time window of a rule, independent of any persistence.
///
/// A window whose end is at or before its start crosses midnight: 22:00 → 06:00
/// starts on an enabled day and ends the following morning. `start == end`
/// means a full 24-hour window.
nonisolated struct RuleSchedule: Hashable, Sendable {
    var startMinutes: Int
    var endMinutes: Int
    var days: Set<Weekday>

    var crossesMidnight: Bool { endMinutes <= startMinutes }

    var durationMinutes: Int {
        crossesMidnight
            ? RuleSchedule.minutesPerDay - startMinutes + endMinutes
            : endMinutes - startMinutes
    }

    /// The window containing `date`, if the schedule is active at that moment.
    ///
    /// Checks today's window and, for midnight-crossing schedules, the window
    /// that started yesterday. The day a window *starts* on is the day that
    /// must be enabled.
    func activeWindow(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        for dayOffset in [0, -1] {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
                let window = window(onDayContaining: day, calendar: calendar),
                window.start <= date, date < window.end
            else { continue }
            return window
        }
        return nil
    }

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        activeWindow(containing: date, calendar: calendar) != nil
    }

    /// The next moment the schedule will begin a window strictly after `date`.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for dayOffset in 0...7 {
            guard
                let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
                let window = window(onDayContaining: day, calendar: calendar),
                window.start > date
            else { continue }
            return window.start
        }
        return nil
    }

    /// The window starting on the given day, or nil when that weekday is not enabled.
    private func window(onDayContaining day: Date, calendar: Calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: day)
        guard
            let weekday = Weekday(rawValue: calendar.component(.weekday, from: dayStart)),
            days.contains(weekday),
            let start = calendar.date(byAdding: .minute, value: startMinutes, to: dayStart),
            let end = calendar.date(
                byAdding: .minute, value: startMinutes + durationMinutes, to: dayStart
            )
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static let minutesPerDay = 24 * 60
}

extension RuleSchedule {
    /// "09:00" style label for a minutes-from-midnight value.
    static func timeLabel(forMinutes minutes: Int) -> String {
        let clamped = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "09:00 – 17:00" range label used by rule details and preset cards.
    var timeRangeLabel: String {
        "\(Self.timeLabel(forMinutes: startMinutes)) – \(Self.timeLabel(forMinutes: endMinutes))"
    }
}
