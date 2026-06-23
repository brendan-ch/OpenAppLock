//
//  LogRetention.swift
//  OpenAppLock
//

import Foundation

/// Chooses which log files have aged out. A file is pruned when its day bucket
/// is strictly older than `retentionDays` before today (so a 14-day window keeps
/// today through 14 days ago, inclusive).
enum LogRetention {
    static func filesToPrune(
        filenames: [String], today: Date, retentionDays: Int, calendar: Calendar = .current
    ) -> [String] {
        let startOfToday = calendar.startOfDay(for: today)
        guard
            let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: startOfToday)
        else { return [] }
        return filenames.filter { name in
            guard let parsed = LogFilename.parse(name),
                let day = dayDate(parsed.day, calendar: calendar)
            else { return false }
            return day < cutoff
        }
    }

    /// Midnight (local) of a `YYYY-MM-DD` key, or nil if unparseable.
    private static func dayDate(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }
}
