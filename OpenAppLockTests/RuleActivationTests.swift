//
//  RuleActivationTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

/// The single temporal-truth primitive both the UI status and the background
/// enforcement derive from. Schedule rules block by the clock; limit rules block
/// once the day's budget is spent on an enabled day; a pause only surfaces when
/// the rule would otherwise be blocking.
@MainActor
@Suite("Rule activation core")
struct RuleActivationTests {
    let mon10 = date(2025, 1, 6, 10, 0)   // inside the default 09:00–17:00
    let tueMidnight = date(2025, 1, 7, 0, 0)
    let tue9 = date(2025, 1, 7, 9, 0)

    // MARK: Builders

    func scheduleSnapshot(
        start: Int = 9 * 60, end: Int = 17 * 60,
        days: Set<Weekday> = Weekday.weekdays,
        isEnabled: Bool = true, pausedUntil: Date? = nil
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(rule: BlockingRule(
            name: "S",
            configuration: .schedule(ScheduleConfig(startMinutes: start, endMinutes: end)),
            isEnabled: isEnabled,
            days: days,
            pausedUntil: pausedUntil))
    }

    func limitSnapshot(
        limit: Int = 45, days: Set<Weekday> = Weekday.everyDay,
        isEnabled: Bool = true, pausedUntil: Date? = nil
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(rule: BlockingRule(
            name: "L",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: limit)),
            isEnabled: isEnabled,
            days: days,
            pausedUntil: pausedUntil))
    }

    func openSnapshot(maxOpens: Int = 5, days: Set<Weekday> = Weekday.everyDay) -> RuleSnapshotDTO {
        RuleSnapshotDTO(rule: BlockingRule(
            name: "O",
            configuration: .openLimit(OpenLimitConfig(maxOpens: maxOpens)),
            days: days))
    }

    // MARK: Schedule — happy path & boundaries

    @Test("Schedule rule inside its window is active until the window ends")
    func scheduleActiveInsideWindow() {
        #expect(scheduleSnapshot().activation(usage: nil, at: mon10, calendar: utc)
            == .active(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Schedule rule outside its window is inactive with the next start")
    func scheduleInactiveOutsideWindow() {
        #expect(scheduleSnapshot().activation(usage: nil, at: date(2025, 1, 6, 19, 0), calendar: utc)
            == .inactive(nextStart: tue9))
    }

    @Test("Exactly at the window start counts as active")
    func scheduleAtWindowStart() {
        #expect(scheduleSnapshot().activation(usage: nil, at: date(2025, 1, 6, 9, 0), calendar: utc)
            == .active(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Exactly at the window end is no longer active (half-open interval)")
    func scheduleAtWindowEnd() {
        #expect(scheduleSnapshot().activation(usage: nil, at: date(2025, 1, 6, 17, 0), calendar: utc)
            == .inactive(nextStart: tue9))
    }

    @Test("A schedule with no days is inactive with no next start")
    func scheduleEmptyDays() {
        #expect(scheduleSnapshot(days: []).activation(usage: nil, at: mon10, calendar: utc)
            == .inactive(nextStart: nil))
    }

    @Test("A disabled schedule rule is inactive with no next start")
    func scheduleDisabled() {
        #expect(scheduleSnapshot(isEnabled: false).activation(usage: nil, at: mon10, calendar: utc)
            == .inactive(nextStart: nil))
    }

    // MARK: Schedule — pause invariants

    @Test("Paused before the window end reports paused until the pause time")
    func schedulePausedBeforeEnd() {
        #expect(scheduleSnapshot(pausedUntil: date(2025, 1, 6, 15, 0))
            .activation(usage: nil, at: mon10, calendar: utc)
            == .paused(until: date(2025, 1, 6, 15, 0)))
    }

    @Test("Paused past the window end clamps to the window end")
    func schedulePausedAfterEnd() {
        #expect(scheduleSnapshot(pausedUntil: date(2025, 1, 6, 18, 0))
            .activation(usage: nil, at: mon10, calendar: utc)
            == .paused(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("An expired pause no longer affects activation")
    func scheduleExpiredPause() {
        #expect(scheduleSnapshot(pausedUntil: date(2025, 1, 6, 9, 30))
            .activation(usage: nil, at: mon10, calendar: utc)
            == .active(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Pause does not surface while the rule is outside its window")
    func schedulePausedButOutsideWindow() {
        #expect(scheduleSnapshot(pausedUntil: date(2025, 1, 6, 20, 0))
            .activation(usage: nil, at: date(2025, 1, 6, 19, 0), calendar: utc)
            == .inactive(nextStart: tue9))
    }

    // MARK: Schedule — midnight-crossing & full day

    @Test("A midnight-crossing window is active late on the start day")
    func crossingActiveLateNight() {
        let snap = scheduleSnapshot(start: 22 * 60, end: 6 * 60, days: Weekday.everyDay)
        #expect(snap.activation(usage: nil, at: date(2025, 1, 6, 23, 0), calendar: utc)
            == .active(until: date(2025, 1, 7, 6, 0)))
    }

    @Test("A midnight-crossing window is still active the next morning")
    func crossingActiveEarlyMorning() {
        let snap = scheduleSnapshot(start: 22 * 60, end: 6 * 60, days: Weekday.everyDay)
        #expect(snap.activation(usage: nil, at: date(2025, 1, 7, 2, 0), calendar: utc)
            == .active(until: date(2025, 1, 7, 6, 0)))
    }

    @Test("A midnight-crossing window is inactive midday with the evening start next")
    func crossingInactiveMidday() {
        let snap = scheduleSnapshot(start: 22 * 60, end: 6 * 60, days: Weekday.everyDay)
        #expect(snap.activation(usage: nil, at: date(2025, 1, 6, 12, 0), calendar: utc)
            == .inactive(nextStart: date(2025, 1, 6, 22, 0)))
    }

    @Test("A full-day window is active any time on an enabled day")
    func fullDayActive() {
        let snap = scheduleSnapshot(start: 0, end: 0, days: Weekday.everyDay)
        #expect(snap.activation(usage: nil, at: mon10, calendar: utc)
            == .active(until: tueMidnight))
    }

    // MARK: Time limit

    @Test("A spent time-limit budget is active until the next midnight")
    func timeLimitSpent() {
        #expect(limitSnapshot().activation(usage: RuleUsageDTO(minutesUsed: 45), at: mon10, calendar: utc)
            == .active(until: tueMidnight))
    }

    @Test("A time-limit one minute under budget is inactive")
    func timeLimitUnderBudget() {
        #expect(limitSnapshot().activation(usage: RuleUsageDTO(minutesUsed: 44), at: mon10, calendar: utc)
            == .inactive(nextStart: tue9))
    }

    @Test("A time-limit rule without usage data is inactive")
    func timeLimitNoUsage() {
        #expect(limitSnapshot().activation(usage: nil, at: mon10, calendar: utc)
            == .inactive(nextStart: tue9))
    }

    @Test("A spent time-limit not scheduled today is inactive (the scheduled-today guard)")
    func timeLimitSpentButNotScheduledToday() {
        #expect(limitSnapshot(days: [.tuesday])
            .activation(usage: RuleUsageDTO(minutesUsed: 99), at: mon10, calendar: utc)
            == .inactive(nextStart: tue9))
    }

    @Test("A disabled time-limit with a spent budget is inactive with no next start")
    func timeLimitDisabledSpent() {
        #expect(limitSnapshot(isEnabled: false)
            .activation(usage: RuleUsageDTO(minutesUsed: 45), at: mon10, calendar: utc)
            == .inactive(nextStart: nil))
    }

    @Test("A paused spent time-limit clamps the pause to the next midnight")
    func timeLimitPausedSpent() {
        #expect(limitSnapshot(pausedUntil: date(2025, 1, 7, 12, 0))
            .activation(usage: RuleUsageDTO(minutesUsed: 45), at: mon10, calendar: utc)
            == .paused(until: tueMidnight))
    }

    // MARK: Open limit

    @Test("Exhausted opens are active until the next midnight")
    func openLimitExhausted() {
        #expect(openSnapshot().activation(usage: RuleUsageDTO(opensUsed: 5), at: mon10, calendar: utc)
            == .active(until: tueMidnight))
    }

    @Test("Opens under budget are inactive")
    func openLimitUnderBudget() {
        #expect(openSnapshot().activation(usage: RuleUsageDTO(opensUsed: 4), at: mon10, calendar: utc)
            == .inactive(nextStart: tue9))
    }

    // MARK: isBlocking convenience

    @Test("Only the active case is blocking")
    func isBlockingConvenience() {
        #expect(RuleActivation.active(until: tueMidnight).isBlocking)
        #expect(!RuleActivation.paused(until: tueMidnight).isBlocking)
        #expect(!RuleActivation.inactive(nextStart: nil).isBlocking)
    }
}
