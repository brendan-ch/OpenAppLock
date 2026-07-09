//
//  Calendar+NextMidnight.swift
//  OpenAppLock
//

import Foundation

nonisolated extension Calendar {
    /// The first instant of the day after the one containing `date` — the
    /// "Tomorrow" reset point for spent limit budgets.
    func nextMidnight(after date: Date) -> Date? {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date))
    }
}
