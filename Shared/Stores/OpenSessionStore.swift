//
//  OpenSessionStore.swift
//  OpenAppLock
//

import Foundation

/// Read access to in-progress granted "Open" sessions, keyed by rule.
/// `nonisolated` + `Sendable` so the off-main enforcement engine can consult it.
nonisolated protocol OpenSessionReading: AnyObject, Sendable {
    /// Whether a granted open for `ruleID` is still running at `now`.
    func hasActiveSession(for ruleID: UUID, at now: Date) -> Bool
}

/// Records when a granted "Open" expires, per rule, in the shared app-group
/// defaults. Pressing the shield's "Open" button lifts an open-limit rule's
/// shield for ~15 minutes (`MonitoringPlan.openSessionMinutes`); this marker
/// lets the foreground enforcer leave that one rule un-shielded for the life of
/// the session instead of re-locking the app mid-session. The monitor clears it
/// when the session's one-shot activity ends.
nonisolated final class OpenSessionStore: OpenSessionReading, @unchecked Sendable {
    private static let key = "openSessionExpiry"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func hasActiveSession(for ruleID: UUID, at now: Date = .now) -> Bool {
        guard let expiry = expiries[ruleID.uuidString] else { return false }
        return Date(timeIntervalSince1970: expiry) > now
    }

    /// Marks a granted open for `ruleID` running until `expiry`.
    func startSession(for ruleID: UUID, until expiry: Date) {
        var map = expiries
        map[ruleID.uuidString] = expiry.timeIntervalSince1970
        defaults.set(map, forKey: Self.key)
    }

    /// Ends a granted open (its one-shot activity fired, or it is being reset).
    func endSession(for ruleID: UUID) {
        var map = expiries
        map[ruleID.uuidString] = nil
        defaults.set(map, forKey: Self.key)
    }

    private var expiries: [String: TimeInterval] {
        defaults.dictionary(forKey: Self.key) as? [String: TimeInterval] ?? [:]
    }
}

/// In-memory granted sessions for tests and UI-test launches.
/// `@unchecked Sendable`: a test double; mutations are ordered behind the enforcer's `await`.
nonisolated final class MockOpenSessionStore: OpenSessionReading, @unchecked Sendable {
    var activeRuleIDs: Set<UUID> = []

    func hasActiveSession(for ruleID: UUID, at now: Date) -> Bool {
        activeRuleIDs.contains(ruleID)
    }
}
