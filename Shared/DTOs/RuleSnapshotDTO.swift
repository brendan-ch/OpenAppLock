//
//  RuleSnapshotDTO.swift
//  OpenAppLock
//

import Foundation

/// Codable mirror of a rule, written to the app group by the app whenever
/// rules change so the Screen Time extensions (which cannot open the
/// SwiftData store) know what to enforce. Built from a `BlockingRule` via
/// `BlockingRule.dto`; outside the SwiftData store, the rule editors, and the
/// mutation path, this is the type every consumer speaks.
nonisolated struct RuleSnapshotDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var kindRaw: String
    var isEnabled: Bool
    var hardMode: Bool
    var blockAdultContent: Bool
    var selectionModeRaw: String
    var selectionData: Data?
    var dayNumbers: [Int]
    /// Schedule-window bounds, minutes from midnight (mirrors `BlockingRule`).
    /// Only meaningful for `.schedule` rules; limit rules carry 0/0.
    var startMinutes: Int
    var endMinutes: Int
    var dailyLimitMinutes: Int
    var maxOpens: Int
    var pausedUntil: Date?

    var kind: RuleKind { RuleKind(rawValue: kindRaw) ?? .schedule }
    var selectionMode: SelectionMode { SelectionMode(rawValue: selectionModeRaw) ?? .block }
    var days: Set<Weekday> { Set(dayNumbers.compactMap(Weekday.init(rawValue:))) }

    /// The recurring time window this rule blocks, for schedule rules.
    var schedule: RuleSchedule {
        RuleSchedule(startMinutes: startMinutes, endMinutes: endMinutes, days: days)
    }

    func isScheduledToday(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: now)) else {
            return false
        }
        return days.contains(weekday)
    }

    /// Whether the given usage exhausts this rule's daily budget.
    func limitReached(given usage: RuleUsageDTO, at now: Date = .now) -> Bool {
        switch kind {
        case .schedule: false
        case .timeLimit: usage.minutesUsed >= dailyLimitMinutes
        case .openLimit: usage.opensUsed >= maxOpens
        }
    }

    /// Whether the user unblocked this rule for the rest of the day.
    func isPaused(at now: Date) -> Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > now
    }
}

nonisolated extension RuleSnapshotDTO {
    private enum CodingKeys: String, CodingKey {
        case id, name, kindRaw, isEnabled, hardMode, blockAdultContent
        case selectionModeRaw, selectionData, dayNumbers, startMinutes, endMinutes
        case dailyLimitMinutes, maxOpens, pausedUntil
    }

    /// Decodes tolerantly so snapshots written before `startMinutes`/`endMinutes`
    /// existed still load (defaulting the window to 0) instead of failing the
    /// whole batch — which would blind the extensions until the app reopened.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kindRaw = try container.decode(String.self, forKey: .kindRaw)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        hardMode = try container.decode(Bool.self, forKey: .hardMode)
        blockAdultContent = try container.decode(Bool.self, forKey: .blockAdultContent)
        selectionModeRaw = try container.decode(String.self, forKey: .selectionModeRaw)
        selectionData = try container.decodeIfPresent(Data.self, forKey: .selectionData)
        dayNumbers = try container.decode([Int].self, forKey: .dayNumbers)
        startMinutes = try container.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 0
        endMinutes = try container.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 0
        dailyLimitMinutes = try container.decode(Int.self, forKey: .dailyLimitMinutes)
        maxOpens = try container.decode(Int.self, forKey: .maxOpens)
        pausedUntil = try container.decodeIfPresent(Date.self, forKey: .pausedUntil)
    }
}
