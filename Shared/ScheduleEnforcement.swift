//
//  ScheduleEnforcement.swift
//  OpenAppLock
//

import Foundation

/// Background reaction for schedule (time-window) rules. The monitor extension
/// calls `reconcile` at each window boundary; it recomputes the rule's live
/// schedule state from its snapshot and applies or clears the shield to match.
///
/// This intentionally mirrors what `RuleEnforcer.refresh` does for schedule
/// rules in the foreground, so the background and foreground paths never
/// disagree. Recomputing (rather than blindly shielding on start / clearing on
/// end) also makes the two activities of a midnight-crossing window — and any
/// late or duplicated interval callback — converge on the correct state.
struct ScheduleEnforcement {
    let snapshots: RuleSnapshotStore
    let shields: ShieldApplying

    func reconcile(ruleID: UUID, now: Date = .now, calendar: Calendar = .current) {
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.kind == .schedule else {
            return
        }
        if snapshot.isEnabled, !snapshot.isPaused(at: now),
           snapshot.schedule.isActive(at: now, calendar: calendar) {
            shields.applyShield(
                ruleID: snapshot.id,
                selectionData: snapshot.selectionData,
                mode: snapshot.selectionMode,
                blockAdultContent: snapshot.blockAdultContent
            )
        } else {
            shields.clearShield(ruleID: snapshot.id)
        }
    }
}
