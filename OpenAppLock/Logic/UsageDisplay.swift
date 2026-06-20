//
//  UsageDisplay.swift
//  OpenAppLock
//

import Foundation

/// Strings for the home- and rules-list rows. Used values clamp to the budget
/// so overshoot (thresholds can fire late) never reads "50m of 45m".
enum UsageDisplay {
    /// The Home-list subtitle: the rule's type, then its live context, so the
    /// kind reads without relying on the icon ("Time Limit · 18m of 45m used",
    /// "Schedule · 6h left"). The Rules list omits the type prefix because its
    /// section header already conveys it.
    static func homeSubtitle(
        for rule: BlockingRule, status: RuleStatus, usage: RuleUsage, relativeTo now: Date
    ) -> String {
        "\(rule.kind.displayName) · \(rule.rowContext(for: status, usage: usage, relativeTo: now))"
    }

    /// "18m of 45m used" / "2 of 5 opens". Empty for schedule rules, which have
    /// no usage budget. ("today" is implied — usage always covers the current day.)
    static func usagePhrase(for rule: BlockingRule, usage: RuleUsage, asOf now: Date) -> String {
        switch rule.configuration {
        case .schedule:
            ""
        case .timeLimit(let config):
            "\(min(usage.effectiveMinutesUsed(asOf: now), config.dailyLimitMinutes))m of "
                + "\(config.dailyLimitMinutes)m used"
        case .openLimit(let config):
            "\(min(usage.opensUsed, config.maxOpens)) of \(config.maxOpens) opens"
        }
    }

    /// "45m / day" / "5 opens / day" — the plain daily allowance, shown while a
    /// limit rule has no usage recorded today. Empty for schedule rules.
    static func budgetPhrase(for rule: BlockingRule) -> String {
        switch rule.configuration {
        case .schedule:
            ""
        case .timeLimit(let config):
            "\(config.dailyLimitMinutes)m / day"
        case .openLimit(let config):
            "\(config.maxOpens) opens / day"
        }
    }
}
