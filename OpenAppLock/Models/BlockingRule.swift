//
//  BlockingRule.swift
//  OpenAppLock
//

import Foundation
import SwiftData

/// A recurring screen-time blocking rule.
///
/// The kind-specific options live in a `RuleConfiguration` sum type, exposed
/// through the computed `configuration` bridge below. The raw per-kind columns
/// (`startMinutes`, `selectionModeRaw`, `dailyLimitMinutes`, …) are persistence
/// detail: they are read and written *only* via `configuration`, which keeps a
/// rule from ever carrying another kind's options (e.g. a Time Limit rule can
/// never hold a Block/Allow-Only mode — see `applyConfiguration`).
///
/// Times are stored as minutes from midnight so the schedule repeats cleanly and
/// is independent of time zones at creation. A window whose end is at or before
/// its start (e.g. 22:00 → 06:00) crosses midnight into the following day.
@Model
final class BlockingRule {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var isEnabled: Bool
    /// Hard block: while the rule is active it cannot be disabled, edited, or paused.
    var hardMode: Bool
    /// The reusable app list this rule blocks (or allows, in Allow Only mode).
    ///
    /// Deliberately not an `init` parameter: SwiftData relationship properties
    /// must only be assigned once both models are inserted in a context —
    /// writing them on unmanaged instances traps intermittently inside
    /// SwiftData (EXC_BREAKPOINT on the next insert/save).
    var appList: AppList?
    /// Legacy inline selection, superseded by `appList`. Kept only so
    /// `AppListMigration` can read pre-app-list stores; always nil afterwards.
    var selectionData: Data?
    /// Legacy denormalized count; superseded by `appList?.selectionCount`.
    var selectionCount: Int
    var dayNumbers: [Int]
    /// When set, the rule's current block is temporarily paused (user tapped Pause).
    /// Cleared automatically once the date passes; never set while Hard Mode is active.
    var pausedUntil: Date?
    var createdAt: Date

    // MARK: Raw per-kind storage (access via `configuration`)

    /// Schedule-window bounds, minutes from midnight. Meaningful for `.schedule`.
    var startMinutes: Int
    var endMinutes: Int
    /// Schedule-only; forced to `.block` for limit kinds by `applyConfiguration`.
    var selectionModeRaw: String
    /// Daily usage budget for `.timeLimit` rules.
    var dailyLimitMinutes: Int
    /// Daily open budget for `.openLimit` rules.
    var maxOpens: Int

    init(
        id: UUID = UUID(),
        name: String,
        configuration: RuleConfiguration = .schedule(ScheduleConfig()),
        isEnabled: Bool = true,
        hardMode: Bool = false,
        days: Set<Weekday> = Weekday.weekdays,
        pausedUntil: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.hardMode = hardMode
        self.appList = nil
        self.selectionData = nil
        self.selectionCount = 0
        self.dayNumbers = days.map(\.rawValue).sorted()
        self.pausedUntil = pausedUntil
        self.createdAt = createdAt
        // Raw per-kind columns start at the default values, then the
        // configuration overwrites the ones that apply to its kind.
        self.kindRaw = configuration.kind.rawValue
        self.startMinutes = 9 * 60
        self.endMinutes = 17 * 60
        self.selectionModeRaw = SelectionMode.block.rawValue
        self.dailyLimitMinutes = 45
        self.maxOpens = 5
        applyConfiguration(configuration)
    }

    /// The kind-specific options of this rule. Reading assembles the sum type
    /// from the raw columns; writing routes through `applyConfiguration`, which
    /// keeps the schedule-only options off limit rules.
    var configuration: RuleConfiguration {
        get {
            switch kind {
            case .schedule:
                .schedule(
                    ScheduleConfig(
                        startMinutes: startMinutes,
                        endMinutes: endMinutes,
                        selectionMode: selectionMode))
            case .timeLimit:
                .timeLimit(TimeLimitConfig(dailyLimitMinutes: dailyLimitMinutes))
            case .openLimit:
                .openLimit(OpenLimitConfig(maxOpens: maxOpens))
            }
        }
        set { applyConfiguration(newValue) }
    }

    /// Writes a configuration onto the raw columns. Limit kinds explicitly
    /// reset the Schedule-only options so a rule can never carry a Block /
    /// Allow-Only mode unless it is a Schedule rule.
    private func applyConfiguration(_ configuration: RuleConfiguration) {
        kindRaw = configuration.kind.rawValue
        switch configuration {
        case .schedule(let config):
            startMinutes = config.startMinutes
            endMinutes = config.endMinutes
            selectionModeRaw = config.selectionMode.rawValue
        case .timeLimit(let config):
            dailyLimitMinutes = config.dailyLimitMinutes
            selectionModeRaw = SelectionMode.block.rawValue
        case .openLimit(let config):
            maxOpens = config.maxOpens
            selectionModeRaw = SelectionMode.block.rawValue
        }
    }

    var kind: RuleKind {
        get { RuleKind(rawValue: kindRaw) ?? .schedule }
        set { kindRaw = newValue.rawValue }
    }

    /// How this rule interprets its app list. Always `.block` for limit kinds.
    var selectionMode: SelectionMode {
        SelectionMode(rawValue: selectionModeRaw) ?? .block
    }

    var days: Set<Weekday> {
        get { Set(dayNumbers.compactMap(Weekday.init(rawValue:))) }
        set { dayNumbers = newValue.map(\.rawValue).sorted() }
    }

    var schedule: RuleSchedule {
        RuleSchedule(startMinutes: startMinutes, endMinutes: endMinutes, days: days)
    }
}

extension BlockingRule {
    /// The order rules appear in every list that shows them — the Rules tab's
    /// kind sections and the Home tab's "Currently Blocking" / "Active Rules"
    /// rows: alphabetical by name (localized, case-insensitive), with creation
    /// date breaking ties so rules sharing a name keep a stable order. Those
    /// views fetch with this via `@Query(sort:)`.
    ///
    /// Kept in an extension to mirror `AppList.displayOrder`, whose `@Model`-body
    /// placement demonstrably broke synthesized `Hashable` for a value type that
    /// holds it (`RuleDraft`). No value type relies on `BlockingRule`'s synthesized
    /// `Hashable` today, so here the extension is precautionary, not required.
    static let displayOrder: [SortDescriptor<BlockingRule>] = [
        SortDescriptor(\.name, comparator: .localizedStandard),
        SortDescriptor(\.createdAt),
    ]
}
