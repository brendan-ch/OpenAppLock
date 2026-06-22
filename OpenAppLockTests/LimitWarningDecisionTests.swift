//
//  LimitWarningDecisionTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Limit warning decision")
struct LimitWarningDecisionTests {
    private func freshDefaults() -> UserDefaults {
        let name = "limit-warning-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Preferences with the time-limit notification fully enabled (authorized +
    /// toggle on).
    private func enabledPreferences() -> NotificationPreferences {
        let defaults = freshDefaults()
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
        defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        return NotificationPreferences(defaults: defaults)
    }

    private func preferences(authorized: Bool, toggle: Bool) -> NotificationPreferences {
        let defaults = freshDefaults()
        defaults.set(authorized, forKey: AppGroup.notificationsAuthorizedKey)
        defaults.set(toggle, forKey: AppGroup.notifyTimeLimitEndingKey)
        return NotificationPreferences(defaults: defaults)
    }

    private func timeLimitSnapshot(
        kind: RuleKind = .timeLimit, limit: Int = 60, days: Set<Weekday> = [.monday],
        enabled: Bool = true, paused: Date? = nil
    ) -> RuleSnapshot {
        RuleSnapshot(
            id: UUID(), name: "Social", kindRaw: kind.rawValue, isEnabled: enabled,
            hardMode: false, blockAdultContent: false, selectionModeRaw: "block",
            selectionData: Data([1]), dayNumbers: days.map(\.rawValue),
            startMinutes: 0, endMinutes: 0, dailyLimitMinutes: limit, maxOpens: 3,
            pausedUntil: paused)
    }

    // Anchor: Monday 2025-01-06, noon, UTC.
    private let mondayNoon = date(AnchorWeek.monday.year, AnchorWeek.monday.month, AnchorWeek.monday.day, 12, 0)

    @Test("Eligible rule produces warning content")
    func eligible() {
        let content = LimitWarningDecision.content(
            for: timeLimitSnapshot(), usage: RuleUsage(minutesUsed: 55),
            preferences: enabledPreferences(), now: mondayNoon, calendar: utc)
        #expect(content != nil)
        #expect(content?.body.contains("5 minutes") == true)
        #expect(content?.title == "Time limit almost up")
    }

    @Test("No content when the toggle is off or unauthorized")
    func gatedByPreferences() {
        let snap = timeLimitSnapshot()
        #expect(
            LimitWarningDecision.content(
                for: snap, usage: RuleUsage(minutesUsed: 55),
                preferences: preferences(authorized: true, toggle: false),
                now: mondayNoon, calendar: utc) == nil)
        #expect(
            LimitWarningDecision.content(
                for: snap, usage: RuleUsage(minutesUsed: 55),
                preferences: preferences(authorized: false, toggle: true),
                now: mondayNoon, calendar: utc) == nil)
    }

    @Test("No content for ineligible rule states")
    func ineligibleStates() {
        let prefs = enabledPreferences()
        let usage = RuleUsage(minutesUsed: 55)
        // Nil snapshot.
        #expect(
            LimitWarningDecision.content(
                for: nil, usage: usage, preferences: prefs, now: mondayNoon, calendar: utc) == nil)
        // Disabled.
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(enabled: false), usage: usage, preferences: prefs,
                now: mondayNoon, calendar: utc) == nil)
        // Paused past now.
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(paused: mondayNoon.addingTimeInterval(3600)),
                usage: usage, preferences: prefs, now: mondayNoon, calendar: utc) == nil)
        // Not scheduled today (Monday rule asked about... Tuesday-only rule).
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(days: [.tuesday]), usage: usage, preferences: prefs,
                now: mondayNoon, calendar: utc) == nil)
        // Already at/over the limit (block already fired).
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(), usage: RuleUsage(minutesUsed: 60), preferences: prefs,
                now: mondayNoon, calendar: utc) == nil)
        // Wrong kinds.
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(kind: .openLimit), usage: usage, preferences: prefs,
                now: mondayNoon, calendar: utc) == nil)
        #expect(
            LimitWarningDecision.content(
                for: timeLimitSnapshot(kind: .schedule), usage: usage, preferences: prefs,
                now: mondayNoon, calendar: utc) == nil)
    }
}
