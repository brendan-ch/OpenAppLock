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
        for snapshot: RuleSnapshotDTO, status: RuleStatus, usage: RuleUsage, relativeTo now: Date
    ) -> String {
        "\(snapshot.kind.displayName) · \(snapshot.rowContext(for: status, usage: usage, relativeTo: now))"
    }

    /// "18m of 45m used" / "2 of 5 opens". Empty for schedule rules, which have
    /// no usage budget. ("today" is implied — usage always covers the current day.)
    static func usagePhrase(for snapshot: RuleSnapshotDTO, usage: RuleUsage, asOf now: Date) -> String {
        switch snapshot.kind {
        case .schedule:
            ""
        case .timeLimit:
            "\(min(usage.effectiveMinutesUsed(asOf: now), snapshot.dailyLimitMinutes))m of "
                + "\(snapshot.dailyLimitMinutes)m used"
        case .openLimit:
            "\(min(usage.opensUsed, snapshot.maxOpens)) of \(snapshot.maxOpens) opens"
        }
    }

    /// "45m / day" / "5 opens / day" — the plain daily allowance, shown while a
    /// limit rule has no usage recorded today. Empty for schedule rules.
    static func budgetPhrase(for snapshot: RuleSnapshotDTO) -> String {
        switch snapshot.kind {
        case .schedule:
            ""
        case .timeLimit:
            "\(snapshot.dailyLimitMinutes)m / day"
        case .openLimit:
            "\(snapshot.maxOpens) opens / day"
        }
    }
}
