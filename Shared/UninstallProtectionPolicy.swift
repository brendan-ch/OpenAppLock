//
//  UninstallProtectionPolicy.swift
//  OpenAppLock
//

import Foundation

/// Snapshot-based mirror of the uninstall-protection decision in `RulePolicy`,
/// living in `Shared` so the Screen Time extensions (which cannot open the
/// SwiftData store) can recompute it in the background from `RuleSnapshot`s.
///
/// The active / hard-locked semantics deliberately match
/// `BlockingRule.status(...).isActive` exactly so the foreground and background
/// paths never disagree; a parity unit test enforces this.
enum UninstallProtectionPolicy {
    /// Whether device app removal should be denied right now: the user opted in
    /// (`enabled`) *and* some snapshot is actively blocking with Hard Mode on.
    static func shouldDenyAppRemoval(
        snapshots: [RuleSnapshot], enabled: Bool,
        usageFor: (RuleSnapshot) -> RuleUsage? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        enabled && isAnyHardLocked(snapshots: snapshots, usageFor: usageFor, at: now, calendar: calendar)
    }

    /// Whether any snapshot is currently a hard block.
    static func isAnyHardLocked(
        snapshots: [RuleSnapshot],
        usageFor: (RuleSnapshot) -> RuleUsage? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshots.contains {
            isHardLocked($0, usage: usageFor($0), at: now, calendar: calendar)
        }
    }

    /// True while the snapshot is actively blocking with Hard Mode on.
    static func isHardLocked(
        _ snapshot: RuleSnapshot, usage: RuleUsage? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshot.hardMode && isActive(snapshot, usage: usage, at: now, calendar: calendar)
    }

    /// Whether the snapshot is actively blocking right now. Mirrors
    /// `BlockingRule.status(...).isActive`: schedule rules block by the clock;
    /// limit rules block once the day's budget is spent on an enabled day. A
    /// paused (unblocked) rule is never active.
    static func isActive(
        _ snapshot: RuleSnapshot, usage: RuleUsage? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard snapshot.isEnabled, !snapshot.isPaused(at: now) else { return false }
        switch snapshot.kind {
        case .schedule:
            return snapshot.schedule.isActive(at: now, calendar: calendar)
        case .timeLimit, .openLimit:
            guard let usage, snapshot.isScheduledToday(at: now, calendar: calendar) else {
                return false
            }
            return snapshot.limitReached(given: usage)
        }
    }
}
