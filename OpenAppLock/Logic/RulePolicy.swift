//
//  RulePolicy.swift
//  OpenAppLock
//

import Foundation

/// Gates every mutation of a rule. This is where Hard Mode is enforced:
/// while a hard-mode rule is actively blocking, nothing about it can be
/// weakened until the window ends.
///
/// The read-only gates are predicates over a `RuleSnapshotDTO` and derive their
/// "actively blocking" judgement from the shared `RuleActivation` primitive, so
/// the foreground gates and the background (extension) enforcement can never
/// disagree. The one mutation, `unblock`, still takes the `BlockingRule` it
/// pauses.
///
/// Limit rules block on spent usage rather than the clock, so their gates
/// take the day's `RuleUsageDTO`; passing nil treats them as not blocking.
enum RulePolicy {
    /// True while the rule is actively blocking with Hard Mode on.
    static func isHardLocked(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshot.hardMode && snapshot.activation(usage: usage, at: now, calendar: calendar).isBlocking
    }

    static func canEdit(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isHardLocked(snapshot, usage: usage, at: now, calendar: calendar)
    }

    static func canDisable(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isHardLocked(snapshot, usage: usage, at: now, calendar: calendar)
    }

    static func canDelete(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isHardLocked(snapshot, usage: usage, at: now, calendar: calendar)
    }

    /// Whether the user may lift the current block early ("Unblock").
    /// Requires an active block and Hard Mode off.
    static func canUnblock(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshot.activation(usage: usage, at: now, calendar: calendar).isBlocking && !snapshot.hardMode
    }

    /// Hard Mode can always be turned on, but never off while the rule is
    /// actively blocking — that is the whole point of a hard block.
    static func canTurnOffHardMode(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isHardLocked(snapshot, usage: usage, at: now, calendar: calendar)
    }

    /// Whether *any* rule is currently a hard block — the condition that locks
    /// app-list editing and (when the user opts in) device app removal.
    static func isAnyHardLocked(
        snapshots: [RuleSnapshotDTO], usageFor: (RuleSnapshotDTO) -> RuleUsageDTO? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        snapshots.contains {
            isHardLocked($0, usage: usageFor($0), at: now, calendar: calendar)
        }
    }

    /// App lists feed active shields, so while any hard-mode rule is actively
    /// blocking, no list may be edited or deleted — changing a list would be a
    /// back door out of the hard block. Creating new lists and picking lists
    /// for other rules stay allowed; they cannot weaken an active block.
    static func canEditAppLists(
        snapshots: [RuleSnapshotDTO], usageFor: (RuleSnapshotDTO) -> RuleUsageDTO? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isAnyHardLocked(snapshots: snapshots, usageFor: usageFor, at: now, calendar: calendar)
    }

    /// Whether the Uninstall Protection toggle may be changed right now. It is
    /// locked while any hard-mode rule is actively blocking — turning it off
    /// mid-block would be an escape hatch, the very thing it exists to prevent.
    static func canToggleUninstallProtection(
        snapshots: [RuleSnapshotDTO], usageFor: (RuleSnapshotDTO) -> RuleUsageDTO? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        !isAnyHardLocked(snapshots: snapshots, usageFor: usageFor, at: now, calendar: calendar)
    }

    /// Whether the device's app removal should be denied right now: the user has
    /// turned on Uninstall Protection *and* a hard block is currently in force.
    /// Engaging this while a hard rule blocks makes the block harder to escape
    /// (the user can't delete the locked apps — or OpenAppLock itself).
    static func shouldDenyAppRemoval(
        snapshots: [RuleSnapshotDTO], enabled: Bool,
        usageFor: (RuleSnapshotDTO) -> RuleUsageDTO? = { _ in nil },
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        enabled && isAnyHardLocked(snapshots: snapshots, usageFor: usageFor, at: now, calendar: calendar)
    }

    /// Pauses the rule's current block. Returns false (and changes nothing)
    /// when unblocking is not allowed. Schedule rules re-arm at their next
    /// window; limit rules re-arm at midnight with the next day's budget.
    @discardableResult
    static func unblock(
        _ rule: BlockingRule, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard canUnblock(rule.dto, usage: usage, at: now, calendar: calendar) else { return false }
        switch rule.kind {
        case .schedule:
            guard let window = rule.schedule.activeWindow(containing: now, calendar: calendar)
            else { return false }
            rule.pausedUntil = window.end
        case .timeLimit, .openLimit:
            guard let midnight = calendar.nextMidnight(after: now) else { return false }
            rule.pausedUntil = midnight
        }
        return true
    }
}
