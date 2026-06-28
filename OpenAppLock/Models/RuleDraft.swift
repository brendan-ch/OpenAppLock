//
//  RuleDraft.swift
//  OpenAppLock
//

import Foundation
import SwiftData

/// Value-type working copy of a rule used by the editors, so cancelling an
/// edit never touches the persisted model. Hashable so it can drive
/// `navigationDestination(item:)`.
///
/// The kind-specific options live in `configuration`, so each editor branch
/// only ever sees the options that belong to its kind (the Schedule editor
/// gets Block/Allow-Only mode; the limit editors do not).
struct RuleDraft: Hashable {
    var name: String
    var days: Set<Weekday>
    var hardMode: Bool
    /// Reference to the persisted list the rule will use. App lists are
    /// managed (created/edited) directly by the picker, so the draft only
    /// carries the pointer.
    var appList: AppList?
    var configuration: RuleConfiguration

    var kind: RuleKind { configuration.kind }

    /// A fresh draft for a new rule of the given kind, using the default
    /// values (9–5 weekdays schedule, 45m/day, 5 opens/day).
    init(kind: RuleKind) {
        self.name = kind.defaultRuleName
        self.days = Weekday.weekdays
        self.hardMode = false
        self.appList = nil
        self.configuration = .default(for: kind)
    }

    init(rule: BlockingRule) {
        self.name = rule.name
        self.days = rule.days
        self.hardMode = rule.hardMode
        self.appList = rule.appList
        self.configuration = rule.configuration
    }

    init(preset: RulePreset) {
        self.init(kind: .schedule)
        self.name = preset.name
        self.days = preset.days
        self.configuration = .schedule(
            ScheduleConfig(startMinutes: preset.startMinutes, endMinutes: preset.endMinutes))
    }

    /// Writes the draft back onto a rule. The rule (and the chosen list) must
    /// already be inserted in a context: SwiftData relationships may only be
    /// assigned between managed models (see `BlockingRule.appList`).
    func apply(to rule: BlockingRule) {
        rule.name = name
        rule.days = days
        rule.hardMode = hardMode
        rule.configuration = configuration
        if rule.appList !== appList {
            rule.appList = appList
        }
        Diag.log(
            .rule, .event,
            "commit rule-\(rule.id.uuidString.prefix(8)) \"\(name)\" \(rule.kindRaw) hard=\(hardMode) enabled=\(rule.isEnabled) list=\(appList?.name ?? "none")")
    }

    /// Creates and inserts a new rule from this draft. The rule is inserted
    /// *before* the draft is applied so the app-list relationship is only
    /// ever written on a managed model.
    @discardableResult
    func insertRule(into context: ModelContext) -> BlockingRule {
        let rule = BlockingRule(name: name, configuration: configuration)
        context.insert(rule)
        apply(to: rule)
        return rule
    }

    /// Trims the name, falling back to the kind's default when it is empty.
    /// (Block / Allow Only no longer needs sanitizing: the sum type makes it
    /// impossible for a limit draft to carry a selection mode at all.)
    func sanitized() -> RuleDraft {
        var copy = self
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        copy.name = trimmed.isEmpty ? kind.defaultRuleName : trimmed
        return copy
    }

    var schedule: RuleSchedule {
        RuleSchedule(
            startMinutes: scheduleConfig.startMinutes,
            endMinutes: scheduleConfig.endMinutes,
            days: days)
    }
}

extension RuleDraft {
    /// Typed projections of the active configuration, used to bind editor
    /// controls. The getter returns kind defaults when the draft is a
    /// different kind; each editor only reads the projection for its own kind,
    /// and writing through it repackages the configuration to that kind.
    var scheduleConfig: ScheduleConfig {
        get { configuration.scheduleConfig ?? ScheduleConfig() }
        set { configuration = .schedule(newValue) }
    }

    var timeLimitConfig: TimeLimitConfig {
        get { configuration.timeLimitConfig ?? TimeLimitConfig() }
        set { configuration = .timeLimit(newValue) }
    }

    var openLimitConfig: OpenLimitConfig {
        get { configuration.openLimitConfig ?? OpenLimitConfig() }
        set { configuration = .openLimit(newValue) }
    }
}
