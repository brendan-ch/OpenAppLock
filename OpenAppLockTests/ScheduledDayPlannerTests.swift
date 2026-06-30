//
//  ScheduledDayPlannerTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Scheduled day planner")
struct ScheduledDayPlannerTests {
    @Test("Upcoming day-starts include today when scheduled, then the next scheduled days")
    func everyDayHorizon() {
        // 2025-01-06 is a Monday (10:00). Every-day rule → today + tomorrow.
        let now = date(2025, 1, 6, 10, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.everyDay, from: now, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 6), date(2025, 1, 7)])
    }

    @Test("Upcoming day-starts skip non-scheduled weekdays")
    func weekdaysHorizonFromFriday() {
        // 2025-01-10 is a Friday. Weekdays-only → Friday, then Monday (skips weekend).
        let friday = date(2025, 1, 10, 9, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.weekdays, from: friday, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 10), date(2025, 1, 13)])
    }

    @Test("Upcoming day-starts start from the next scheduled day when today is not scheduled")
    func startsAtNextScheduledDay() {
        // 2025-01-11 is a Saturday; weekdays-only → next is Monday + Tuesday.
        let saturday = date(2025, 1, 11, 9, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.weekdays, from: saturday, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 13), date(2025, 1, 14)])
    }

    @Test("No scheduled days yields an empty horizon")
    func emptyDays() {
        let now = date(2025, 1, 6, 10, 0)
        #expect(
            ScheduledDayPlanner.upcomingScheduledDayStarts(
                days: [], from: now, count: 2, calendar: utc).isEmpty)
    }

    @Test("Next scheduled day-start after a given day skips non-scheduled weekdays")
    func nextAfter() {
        // After Friday 2025-01-10, weekdays-only → Monday 2025-01-13.
        let next = ScheduledDayPlanner.nextScheduledDayStart(
            after: date(2025, 1, 10), days: Weekday.weekdays, calendar: utc)
        #expect(next == date(2025, 1, 13))
    }
}
