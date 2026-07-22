//
//  ShieldLookupTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

/// Arbitration of which shield a token gets when several rules cover the same
/// app: the open-limit "Open" offer must be withheld whenever another covering
/// rule is actively blocking, because granting an open clears only the
/// open-limit rule's own store and the other rule's shield would keep the app
/// blocked (stranding the user and wasting an open).
@MainActor
@Suite("Shield lookup arbitration")
struct ShieldLookupTests {
    /// Monday 10:00 of the anchor week.
    let monday = date(2025, 1, 6, 10, 0)

    private func snapshot(
        kind: RuleKind, id: UUID = UUID(), enabled: Bool = true,
        start: Int = 0, end: Int = 0,
        days: Set<Weekday> = Weekday.everyDay,
        limit: Int = 45, maxOpens: Int = 5, pausedUntil: Date? = nil
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(
            id: id, name: "Rule", kindRaw: kind.rawValue, isEnabled: enabled,
            hardMode: false, selectionModeRaw: "block",
            selectionData: Data([1]), dayNumbers: days.map(\.rawValue),
            startMinutes: start, endMinutes: end,
            dailyLimitMinutes: limit, maxOpens: maxOpens, pausedUntil: pausedUntil
        )
    }

    private func lookup(
        covering: [RuleSnapshotDTO], usages: [UUID: RuleUsageDTO] = [:],
        activeSessions: Set<UUID> = [], at now: Date? = nil
    ) -> RuleSnapshotDTO? {
        ShieldLookup.openLimitSnapshot(
            amongCovering: covering,
            usage: { usages[$0] ?? RuleUsageDTO() },
            hasActiveOpenSession: { activeSessions.contains($0) },
            at: now ?? monday, calendar: utc)
    }

    @Test("The sole covering open-limit rule keeps its Open offer")
    func openLimitAloneIsReturned() {
        let openLimit = snapshot(kind: .openLimit)
        #expect(lookup(covering: [openLimit])?.id == openLimit.id)
    }

    @Test("A covering schedule rule with an active window suppresses the Open offer")
    func activeScheduleWindowSuppresses() {
        let openLimit = snapshot(kind: .openLimit)
        let schedule = snapshot(kind: .schedule, start: 9 * 60, end: 17 * 60)
        #expect(lookup(covering: [openLimit, schedule]) == nil)
        // Order of the covering rules must not matter.
        #expect(lookup(covering: [schedule, openLimit]) == nil)
    }

    @Test("A covering schedule rule outside its window does not suppress")
    func inactiveScheduleWindowDoesNotSuppress() {
        let openLimit = snapshot(kind: .openLimit)
        let schedule = snapshot(kind: .schedule, start: 22 * 60, end: 6 * 60)
        #expect(lookup(covering: [openLimit, schedule])?.id == openLimit.id)
    }

    @Test("A covering time-limit rule with a spent budget suppresses the Open offer")
    func spentTimeLimitSuppresses() {
        let openLimit = snapshot(kind: .openLimit)
        let timeLimit = snapshot(kind: .timeLimit, limit: 45)
        let usages = [timeLimit.id: RuleUsageDTO(minutesUsed: 45)]
        #expect(lookup(covering: [openLimit, timeLimit], usages: usages) == nil)
    }

    @Test("A covering time-limit rule under budget does not suppress")
    func underBudgetTimeLimitDoesNotSuppress() {
        let openLimit = snapshot(kind: .openLimit)
        let timeLimit = snapshot(kind: .timeLimit, limit: 45)
        let usages = [timeLimit.id: RuleUsageDTO(minutesUsed: 20)]
        #expect(lookup(covering: [openLimit, timeLimit], usages: usages)?.id == openLimit.id)
    }

    @Test("A paused blocking rule does not suppress (its block is lifted)")
    func pausedBlockerDoesNotSuppress() {
        let openLimit = snapshot(kind: .openLimit)
        let schedule = snapshot(
            kind: .schedule, start: 9 * 60, end: 17 * 60,
            pausedUntil: date(2025, 1, 6, 10, 10))
        #expect(lookup(covering: [openLimit, schedule])?.id == openLimit.id)
    }

    @Test("A disabled blocking rule does not suppress")
    func disabledBlockerDoesNotSuppress() {
        let openLimit = snapshot(kind: .openLimit)
        let schedule = snapshot(kind: .schedule, enabled: false, start: 9 * 60, end: 17 * 60)
        #expect(lookup(covering: [openLimit, schedule])?.id == openLimit.id)
    }

    @Test("The candidate's own spent budget does not suppress it")
    func exhaustedCandidateStillReturned() {
        // The exhausted open-limit shield must keep rendering with its counts
        // ("no opens left"), which needs the snapshot — its own blocking state
        // is not "another rule's block".
        let openLimit = snapshot(kind: .openLimit, maxOpens: 2)
        let usages = [openLimit.id: RuleUsageDTO(opensUsed: 2)]
        #expect(lookup(covering: [openLimit], usages: usages)?.id == openLimit.id)
    }

    @Test("No covering open-limit rule means no Open offer")
    func noOpenLimitAmongCovering() {
        let schedule = snapshot(kind: .schedule, start: 9 * 60, end: 17 * 60)
        #expect(lookup(covering: [schedule]) == nil)
        #expect(lookup(covering: []) == nil)
    }

    @Test("A disabled open-limit rule is not an Open candidate")
    func disabledOpenLimitIsNotCandidate() {
        let openLimit = snapshot(kind: .openLimit, enabled: false)
        #expect(lookup(covering: [openLimit]) == nil)
    }

    @Test("Another open-limit rule with a spent budget suppresses the Open offer")
    func otherSpentOpenLimitSuppresses() {
        let openLimit = snapshot(kind: .openLimit, maxOpens: 5)
        let spent = snapshot(kind: .openLimit, maxOpens: 1)
        let usages = [spent.id: RuleUsageDTO(opensUsed: 1)]
        #expect(lookup(covering: [openLimit, spent], usages: usages) == nil)
    }

    @Test("A spent open-limit rule inside its granted session does not suppress")
    func otherOpenLimitInSessionDoesNotSuppress() {
        // Its store is cleared for the session, so it is not shielding right now.
        let openLimit = snapshot(kind: .openLimit, maxOpens: 5)
        let inSession = snapshot(kind: .openLimit, maxOpens: 1)
        let usages = [inSession.id: RuleUsageDTO(opensUsed: 1)]
        #expect(
            lookup(
                covering: [openLimit, inSession], usages: usages,
                activeSessions: [inSession.id])?.id == openLimit.id)
    }

    @Test("Coverage semantics: Block covers its selection, Allow-Only its complement")
    func selectionCoverageModeSemantics() {
        #expect(ShieldLookup.selectionCoversApplication(mode: .block, selectionContainsToken: true))
        #expect(!ShieldLookup.selectionCoversApplication(mode: .block, selectionContainsToken: false))
        #expect(!ShieldLookup.selectionCoversApplication(mode: .allowOnly, selectionContainsToken: true))
        #expect(ShieldLookup.selectionCoversApplication(mode: .allowOnly, selectionContainsToken: false))

        #expect(ShieldLookup.selectionCoversCategory(mode: .block, selectionContainsToken: true))
        #expect(!ShieldLookup.selectionCoversCategory(mode: .block, selectionContainsToken: false))
        // `.all(except: apps)` shields every category regardless of the selection.
        #expect(ShieldLookup.selectionCoversCategory(mode: .allowOnly, selectionContainsToken: true))
        #expect(ShieldLookup.selectionCoversCategory(mode: .allowOnly, selectionContainsToken: false))
    }

    @Test("A blocking rule not scheduled today does not suppress")
    func notScheduledTodayTimeLimitDoesNotSuppress() {
        let openLimit = snapshot(kind: .openLimit)
        // Spent budget, but the rule only runs on weekends — Monday is free.
        let timeLimit = snapshot(kind: .timeLimit, days: [.saturday, .sunday], limit: 45)
        let usages = [timeLimit.id: RuleUsageDTO(minutesUsed: 45)]
        #expect(lookup(covering: [openLimit, timeLimit], usages: usages)?.id == openLimit.id)
    }
}
