//
//  UsageDisplay.swift
//  OpenAppLock
//

import Foundation

/// Strings for the home- and rules-list rows.
enum UsageDisplay {
    /// The Home-list subtitle: the rule's type, then its live context, so the
    /// kind reads without relying on the icon ("Time Limit · Resets in 8h",
    /// "Schedule · Ends in 6h"). The Rules list omits the type prefix because its
    /// section header already conveys it.
    static func homeSubtitle(
        for snapshot: RuleSnapshotDTO, status: RuleStatus, usage: RuleUsageDTO,
        relativeTo now: Date, calendar: Calendar = .current
    ) -> String {
        CopyKey.usageSubtitleSeparator.string(
            snapshot.kind.displayName,
            snapshot.rowContext(for: status, usage: usage, relativeTo: now, calendar: calendar))
    }
}
