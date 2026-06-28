//
//  RuleConfiguration.swift
//  OpenAppLock
//

import Foundation

/// The kind-specific options of a rule, modelled as a sum type so a rule can
/// only carry the options that belong to its kind. This makes illegal states
/// unrepresentable: an Open Limit rule cannot hold a time window, and a Time
/// Limit rule cannot hold a Block/Allow-Only mode — selection mode is a
/// Schedule-only option. The reasoning: a usage budget over "everything except
/// X" (Allow Only) is not meaningful. Selection mode also belongs to the
/// *rule*, not its app list, so it lives in `ScheduleConfig` rather than on
/// `AppList`.
///
/// Kind-common attributes (name, days, hardMode, isEnabled, appList,
/// pausedUntil) live on the owning `BlockingRule` / `RuleDraft`, not here.
enum RuleConfiguration: Hashable, Sendable {
    case schedule(ScheduleConfig)
    case timeLimit(TimeLimitConfig)
    case openLimit(OpenLimitConfig)

    var kind: RuleKind {
        switch self {
        case .schedule: .schedule
        case .timeLimit: .timeLimit
        case .openLimit: .openLimit
        }
    }

    /// The default configuration for a brand-new rule of the given kind
    /// (9–5 schedule, 45m/day, 5 opens/day).
    static func `default`(for kind: RuleKind) -> RuleConfiguration {
        switch kind {
        case .schedule: .schedule(ScheduleConfig())
        case .timeLimit: .timeLimit(TimeLimitConfig())
        case .openLimit: .openLimit(OpenLimitConfig())
        }
    }

    var scheduleConfig: ScheduleConfig? {
        if case .schedule(let config) = self { config } else { nil }
    }

    var timeLimitConfig: TimeLimitConfig? {
        if case .timeLimit(let config) = self { config } else { nil }
    }

    var openLimitConfig: OpenLimitConfig? {
        if case .openLimit(let config) = self { config } else { nil }
    }
}

/// Schedule-rule options: a recurring time window and how the app list is
/// interpreted. A window whose end is at or before its start crosses midnight.
struct ScheduleConfig: Hashable, Sendable {
    var startMinutes: Int
    var endMinutes: Int
    var selectionMode: SelectionMode

    init(
        startMinutes: Int = 9 * 60,
        endMinutes: Int = 17 * 60,
        selectionMode: SelectionMode = .block
    ) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.selectionMode = selectionMode
    }
}

/// Time Limit option: a daily cumulative-usage budget in minutes.
struct TimeLimitConfig: Hashable, Sendable {
    var dailyLimitMinutes: Int

    init(dailyLimitMinutes: Int = 45) {
        self.dailyLimitMinutes = dailyLimitMinutes
    }
}

/// Open Limit option: a daily budget of app opens.
struct OpenLimitConfig: Hashable, Sendable {
    var maxOpens: Int

    init(maxOpens: Int = 5) {
        self.maxOpens = maxOpens
    }
}
