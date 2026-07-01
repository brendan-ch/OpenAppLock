//
//  RuleKind.swift
//  OpenAppLock
//

import Foundation

/// The three kinds of blocking rules offered on the "New Rule" sheet.
enum RuleKind: String, Codable, CaseIterable, Sendable {
    /// Block selected apps during a recurring time window.
    case schedule
    /// Block selected apps after a daily usage budget is spent.
    case timeLimit
    /// Block selected apps after a number of opens per day.
    case openLimit

    var displayName: String {
        switch self {
        case .schedule: CopyKey.ruleKindScheduleDisplayName.string
        case .timeLimit: CopyKey.ruleKindTimeLimitDisplayName.string
        case .openLimit: CopyKey.ruleKindOpenLimitDisplayName.string
        }
    }

    var exampleText: String {
        switch self {
        case .schedule: CopyKey.ruleKindScheduleExampleText.string
        case .timeLimit: CopyKey.ruleKindTimeLimitExampleText.string
        case .openLimit: CopyKey.ruleKindOpenLimitExampleText.string
        }
    }

    var symbolName: String {
        switch self {
        case .schedule: "calendar"
        case .timeLimit: "hourglass"
        case .openLimit: "lock.fill"
        }
    }

    /// Default name given to a brand-new rule of this kind (e.g. "In the Zone", "Time Keeper").
    var defaultRuleName: String {
        switch self {
        case .schedule: CopyKey.ruleKindDefaultNameSchedule.string
        case .timeLimit: CopyKey.ruleKindDefaultNameTimeLimit.string
        case .openLimit: CopyKey.ruleKindDefaultNameOpenLimit.string
        }
    }
}

/// How the rule's app selection is interpreted.
enum SelectionMode: String, Codable, CaseIterable, Sendable {
    /// Block the selected apps; everything else stays available.
    case block
    /// Block everything except the selected apps.
    case allowOnly

    var displayName: String {
        switch self {
        case .block: CopyKey.selectionModeBlock.string
        case .allowOnly: CopyKey.selectionModeAllowOnly.string
        }
    }
}
