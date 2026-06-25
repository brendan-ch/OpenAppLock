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
    /// The true daily total written by the DeviceActivityReport extension while
    /// the app is foreground; preferred over `minutesUsed` when fresh.
    var authoritativeMinutesUsed: Int?
    /// When the authoritative total was computed.
    var authoritativeAsOf: Date?

    /// How long an authoritative reading is trusted before falling back to the
    /// threshold count. Tunable on device.
    static let authoritativeFreshness: TimeInterval = 120

    /// The daily minutes to use for display and the block decision: the report's
    /// authoritative total when fresh, else the threshold count.
    func effectiveMinutesUsed(
        asOf now: Date, freshness: TimeInterval = RuleUsageDTO.authoritativeFreshness
    ) -> Int {
        if let authoritative = authoritativeMinutesUsed, let asOf = authoritativeAsOf,
           abs(now.timeIntervalSince(asOf)) <= freshness {
            return authoritative
        }
        return minutesUsed
    }
}
