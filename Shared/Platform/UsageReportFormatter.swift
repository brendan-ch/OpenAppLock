//
//  UsageReportFormatter.swift
//  OpenAppLock
//

import Foundation

/// Shapes the rule-detail "Usage" report: today's combined total plus a per-app
/// breakdown. Pure and Shared so the report extension renders it and unit tests
/// cover it (the embedded `DeviceActivityReport` system view itself is
/// device-only and untestable).
nonisolated enum UsageReportFormatter {
    /// "1h 12m" / "45m" / "2h" / "0m" — whole hours and minutes, omitting a zero
    /// part but rendering "0m" for zero.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    /// A single usage figure from raw seconds: "<1m" for any non-zero usage under
    /// a minute, otherwise the whole-minute `duration`; "0m" for none. Shared by
    /// the per-app rows and `todayTotal` so both read the same way.
    static func durationLabel(seconds: Double) -> String {
        guard seconds > 0 else { return "0m" }
        if seconds < 60 { return "<1m" }
        return duration(minutes: Int(seconds / 60))
    }

    /// The total line: "1h 12m today" / "<1m today"; "No usage today" only when
    /// there is no usage at all.
    static func todayTotal(seconds: Double) -> String {
        guard seconds > 0 else { return "No usage today" }
        return "\(durationLabel(seconds: seconds)) today"
    }

    /// Builds the report payload from raw per-app `(name, seconds)` pairs. Entries
    /// sharing a display name are summed into one row — both the same app across
    /// activity segments and two apps the user can't tell apart — which also keeps
    /// `AppUsageRow.id` (the name) unique. The total flows through `todayTotal`;
    /// rows keep every name with non-zero usage (a sub-minute one reads "<1m"),
    /// sorted by seconds descending (ties broken by name, ascending).
    static func report(apps: [(name: String, seconds: Double)]) -> RuleUsageReportData {
        var secondsByName: [String: Double] = [:]
        for app in apps {
            secondsByName[app.name, default: 0] += app.seconds
        }
        let total = todayTotal(seconds: secondsByName.values.reduce(0, +))
        let rows = secondsByName
            .filter { $0.value > 0 }
            .map { AppUsageRow(name: $0.key, seconds: $0.value) }
            .sorted { lhs, rhs in
                lhs.seconds != rhs.seconds
                    ? lhs.seconds > rhs.seconds   // heaviest app first
                    : lhs.name < rhs.name         // stable tiebreak
            }
        return RuleUsageReportData(total: total, apps: rows)
    }
}

/// Today's combined usage total plus a per-app breakdown, rendered by the report
/// extension's `RuleUsageReportView`.
nonisolated struct RuleUsageReportData: Equatable {
    let total: String
    let apps: [AppUsageRow]
}

/// One app's contribution to a rule's usage today. Carries raw `seconds` — the
/// source for both its label and the heaviest-first sort. The display name is the
/// row identity, so `report` sums entries that share a name into one row.
nonisolated struct AppUsageRow: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let seconds: Double
    var durationLabel: String { UsageReportFormatter.durationLabel(seconds: seconds) }
}
