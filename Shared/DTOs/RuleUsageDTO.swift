//
//  RuleUsageDTO.swift
//  OpenAppLock
//

import Foundation

/// Codable mirror of what a limit rule has consumed on a given day, persisted
/// to the app group by `UsageLedger`. Written by the DeviceActivity monitor
/// (minutes) and shield-action extension (opens); read by the app for display
/// and enforcement. The plain-data payload every consumer speaks, paired with
/// `UsageLedger` which performs the app-group I/O — the same payload/store
/// split as `RuleSnapshotDTO` / `RuleSnapshotStore`.
nonisolated struct RuleUsageDTO: Codable, Equatable {
    var minutesUsed = 0
    var opensUsed = 0
}
