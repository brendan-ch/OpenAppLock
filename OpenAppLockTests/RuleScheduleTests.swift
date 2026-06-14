//
//  RuleScheduleTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("RuleSchedule window math")
struct RuleScheduleTests {
    let nineToFiveWeekdays = RuleSchedule(
        startMinutes: 9 * 60, endMinutes: 17 * 60, days: Weekday.weekdays
    )
    let overnight = RuleSchedule(
        startMinutes: 22 * 60, endMinutes: 6 * 60, days: Weekday.everyDay
    )

    @Test("Active inside a same-day window")
    func activeInsideWindow() {
        let monday10am = date(2025, 1, 6, 10, 0)
        let window = nineToFiveWeekdays.activeWindow(containing: monday10am, calendar: utc)
        #expect(window?.start == date(2025, 1, 6, 9, 0))
        #expect(window?.end == date(2025, 1, 6, 17, 0))
    }

    @Test("Inactive before the window starts and after it ends")
    func inactiveOutsideWindow() {
        #expect(!nineToFiveWeekdays.isActive(at: date(2025, 1, 6, 8, 59), calendar: utc))
        #expect(!nineToFiveWeekdays.isActive(at: date(2025, 1, 6, 17, 0), calendar: utc))
    }

    @Test("Window start is inclusive, end is exclusive")
    func boundaryInclusion() {
        #expect(nineToFiveWeekdays.isActive(at: date(2025, 1, 6, 9, 0), calendar: utc))
        #expect(!nineToFiveWeekdays.isActive(at: date(2025, 1, 6, 17, 0), calendar: utc))
    }

    @Test("Inactive on a disabled day")
    func inactiveOnWeekend() {
        #expect(!nineToFiveWeekdays.isActive(at: date(2025, 1, 11, 12, 0), calendar: utc))
    }

    @Test("Overnight window is active before and after midnight")
    func overnightWindow() {
        // Monday 23:30 — inside Monday's 22:00 → Tuesday 06:00 window.
        let lateMonday = overnight.activeWindow(containing: date(2025, 1, 6, 23, 30), calendar: utc)
        #expect(lateMonday?.start == date(2025, 1, 6, 22, 0))
        #expect(lateMonday?.end == date(2025, 1, 7, 6, 0))

        // Tuesday 02:00 — still inside the window that started Monday.
        let earlyTuesday = overnight.activeWindow(containing: date(2025, 1, 7, 2, 0), calendar: utc)
        #expect(earlyTuesday?.start == date(2025, 1, 6, 22, 0))
        #expect(earlyTuesday?.end == date(2025, 1, 7, 6, 0))

        // The end boundary is exclusive: Tuesday 06:00 is outside Monday's window.
        #expect(overnight.activeWindow(containing: date(2025, 1, 7, 6, 0), calendar: utc) == nil)
    }

    @Test("Overnight window belongs to the day it starts on")
    func overnightDayOwnership() {
        let mondayOnly = RuleSchedule(
            startMinutes: 22 * 60, endMinutes: 6 * 60, days: [.monday]
        )
        // Tuesday 03:00 is inside Monday's window.
        #expect(mondayOnly.isActive(at: date(2025, 1, 7, 3, 0), calendar: utc))
        // Wednesday 03:00 would be Tuesday's window — Tuesday is disabled.
        #expect(!mondayOnly.isActive(at: date(2025, 1, 8, 3, 0), calendar: utc))
        // Monday 23:00 is inside Monday's window.
        #expect(mondayOnly.isActive(at: date(2025, 1, 6, 23, 0), calendar: utc))
    }

    @Test("Equal start and end means a 24-hour window")
    func fullDayWindow() {
        let allDay = RuleSchedule(startMinutes: 600, endMinutes: 600, days: [.monday])
        #expect(allDay.durationMinutes == 24 * 60)
        #expect(allDay.isActive(at: date(2025, 1, 7, 9, 59), calendar: utc))
        #expect(!allDay.isActive(at: date(2025, 1, 7, 10, 0), calendar: utc))
    }

    @Test("Next start on the same day")
    func nextStartSameDay() {
        let next = nineToFiveWeekdays.nextStart(after: date(2025, 1, 6, 8, 0), calendar: utc)
        #expect(next == date(2025, 1, 6, 9, 0))
    }

    @Test("Next start skips disabled days")
    func nextStartSkipsWeekend() {
        let next = nineToFiveWeekdays.nextStart(after: date(2025, 1, 11, 12, 0), calendar: utc)
        #expect(next == date(2025, 1, 13, 9, 0))
    }

    @Test("Next start is strictly after the given moment")
    func nextStartStrictlyAfter() {
        let next = nineToFiveWeekdays.nextStart(after: date(2025, 1, 6, 9, 0), calendar: utc)
        #expect(next == date(2025, 1, 7, 9, 0))
    }

    @Test("No days means no windows and no next start")
    func emptyDays() {
        let never = RuleSchedule(startMinutes: 540, endMinutes: 1020, days: [])
        #expect(!never.isActive(at: date(2025, 1, 6, 10, 0), calendar: utc))
        #expect(never.nextStart(after: date(2025, 1, 6, 10, 0), calendar: utc) == nil)
    }

    @Test("Duration handles normal and overnight windows")
    func duration() {
        #expect(nineToFiveWeekdays.durationMinutes == 8 * 60)
        #expect(overnight.durationMinutes == 8 * 60)
    }

    @Test("Time labels are zero-padded 24h")
    func timeLabels() {
        #expect(RuleSchedule.timeLabel(forMinutes: 9 * 60) == "09:00")
        #expect(RuleSchedule.timeLabel(forMinutes: 17 * 60 + 5) == "17:05")
        #expect(RuleSchedule.timeLabel(forMinutes: 0) == "00:00")
        #expect(nineToFiveWeekdays.timeRangeLabel == "09:00 – 17:00")
    }
}
