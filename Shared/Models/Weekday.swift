//
//  Weekday.swift
//  OpenAppLock
//

import Foundation

/// A day of the week, using `Calendar` weekday numbering (1 = Sunday … 7 = Saturday).
///
/// `nonisolated` because it is a pure value type used from every isolation
/// domain — the background Screen Time extensions and default-argument
/// expressions — under the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: Set<Weekday> = [.saturday, .sunday]
    static let everyDay: Set<Weekday> = Set(Weekday.allCases)

    /// Display order used by the day picker: S M T W T F S.
    static let displayOrder: [Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    /// Single-letter label for the circular day toggles.
    var shortLabel: String {
        switch self {
        case .sunday, .saturday: CopyKey.weekdayShortLabelS.string
        case .monday: CopyKey.weekdayShortLabelM.string
        case .tuesday, .thursday: CopyKey.weekdayShortLabelT.string
        case .wednesday: CopyKey.weekdayShortLabelW.string
        case .friday: CopyKey.weekdayShortLabelF.string
        }
    }

    /// Three-letter abbreviation used in custom day summaries ("Mon, Wed, Fri").
    var abbreviation: String {
        switch self {
        case .sunday: CopyKey.weekdaySundayAbbreviation.string
        case .monday: CopyKey.weekdayMondayAbbreviation.string
        case .tuesday: CopyKey.weekdayTuesdayAbbreviation.string
        case .wednesday: CopyKey.weekdayWednesdayAbbreviation.string
        case .thursday: CopyKey.weekdayThursdayAbbreviation.string
        case .friday: CopyKey.weekdayFridayAbbreviation.string
        case .saturday: CopyKey.weekdaySaturdayAbbreviation.string
        }
    }
}

extension Set<Weekday> {
    /// Human-readable summary shown next to the day picker and in rule details:
    /// "Weekdays", "Weekends", "Every day", "Never", or a list like "Mon, Wed, Fri".
    var summary: String {
        if self == Weekday.everyDay { return CopyKey.weekdayEveryDaySummary.string }
        if self == Weekday.weekdays { return CopyKey.weekdayWeekdaysSummary.string }
        if self == Weekday.weekends { return CopyKey.weekdayWeekendsSummary.string }
        if isEmpty { return CopyKey.weekdayNeverSummary.string }
        return Weekday.displayOrder
            .filter(contains)
            .map(\.abbreviation)
            .joined(separator: ", ")
    }
}
