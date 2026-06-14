//
//  Weekday.swift
//  OpenAppLock
//

import Foundation

/// A day of the week, using `Calendar` weekday numbering (1 = Sunday … 7 = Saturday).
enum Weekday: Int, CaseIterable, Codable, Hashable, Sendable {
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
        case .sunday, .saturday: "S"
        case .monday: "M"
        case .tuesday, .thursday: "T"
        case .wednesday: "W"
        case .friday: "F"
        }
    }

    /// Three-letter abbreviation used in custom day summaries ("Mon, Wed, Fri").
    var abbreviation: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

extension Set<Weekday> {
    /// Human-readable summary shown next to the day picker and in rule details:
    /// "Weekdays", "Weekends", "Every day", "Never", or a list like "Mon, Wed, Fri".
    var summary: String {
        if self == Weekday.everyDay { return "Every day" }
        if self == Weekday.weekdays { return "Weekdays" }
        if self == Weekday.weekends { return "Weekends" }
        if isEmpty { return "Never" }
        return Weekday.displayOrder
            .filter(contains)
            .map(\.abbreviation)
            .joined(separator: ", ")
    }
}
