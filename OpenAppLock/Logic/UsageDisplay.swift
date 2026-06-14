//
//  UsageDisplay.swift
//  OpenAppLock
//

import Foundation

/// Strings for the home screen's Usage section. Used values clamp to the
/// budget so overshoot (thresholds can fire late) never reads "50m of 45m".
enum UsageDisplay {
    /// The usage subtitle prefixed with the rule's type, so the kind is clear
    /// without relying on an icon: "Time Limit · 18m of 45m used today".
    /// Schedule rules (no usage text) fall back to just the type name.
    static func typedSubtitle(for rule: BlockingRule, usage: RuleUsage) -> String {
        let usageText = subtitle(for: rule, usage: usage)
        guard !usageText.isEmpty else { return rule.kind.displayName }
        return "\(rule.kind.displayName) · \(usageText)"
    }

    /// "18m of 45m used today" / "2 of 5 opens today".
    static func subtitle(for rule: BlockingRule, usage: RuleUsage) -> String {
        switch rule.configuration {
        case .schedule:
            ""
        case .timeLimit(let config):
            "\(min(usage.minutesUsed, config.dailyLimitMinutes))m of "
                + "\(config.dailyLimitMinutes)m used today"
        case .openLimit(let config):
            "\(min(usage.opensUsed, config.maxOpens)) of \(config.maxOpens) opens today"
        }
    }

    /// "27m left" / "3 opens left", or the blocked/unblocked state once the
    /// budget is spent.
    static func remainingLabel(for rule: BlockingRule, usage: RuleUsage, isPaused: Bool) -> String {
        guard !rule.limitReached(given: usage) else {
            return isPaused ? "Unblocked until tomorrow" : "Blocked until tomorrow"
        }
        switch rule.configuration {
        case .schedule:
            return ""
        case .timeLimit(let config):
            return "\(config.dailyLimitMinutes - usage.minutesUsed)m left"
        case .openLimit(let config):
            let remaining = config.maxOpens - usage.opensUsed
            return remaining == 1 ? "1 open left" : "\(remaining) opens left"
        }
    }
}
