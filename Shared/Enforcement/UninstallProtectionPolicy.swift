//
//  UninstallProtectionPolicy.swift
//  OpenAppLock
//

import Foundation

/// Snapshot-based mirror of the uninstall-protection decision in `RulePolicy`,
/// living in `Shared` so the Screen Time extensions (which cannot open the
/// SwiftData store) can recompute it in the background from `RuleSnapshotDTO`s.
///
/// The active / hard-locked semantics deliberately match
/// `BlockingRule.status(...).isActive` exactly so the foreground and background
/// paths never disagree; a parity unit test enforces this.
enum UninstallProtectionPolicy {
    /// Whether device app removal should be denied right now: the user opted in
    /// (`enabled`) *and* some snapshot is actively blocking with Hard Mode on.
    static func shouldDenyAppRemoval(
        snapshots: [RuleSnapshotDTO], enabled: Bool,
        usageFor: (RuleSnapshotDTO) -> RuleUsage? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        enabled && isAnyHardLocked(snapshots: snapshots, usageFor: usageFor, at: now, calendar: calendar)
    }

    /// Whether any snapshot is currently a hard block.
    static func isAnyHardLocked(
        snapshots: [RuleSnapshotDTO],
        usageFor: (RuleSnapshotDTO) -> RuleUsage? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshots.contains {
            isHardLocked($0, usage: usageFor($0), at: now, calendar: calendar)
        }
    }

    /// True while the snapshot is actively blocking with Hard Mode on.
    static func isHardLocked(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsage? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshot.hardMode && isActive(snapshot, usage: usage, at: now, calendar: calendar)
    }

    /// Whether the snapshot is actively blocking right now — the single
    /// `RuleActivation` primitive that `BlockingRule.status(...).isActive` also
    /// derives from, so the foreground and background paths cannot disagree.
    static func isActive(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsage? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshot.activation(usage: usage, at: now, calendar: calendar).isBlocking
    }
}
