//
//  ScheduleStartNotificationPlanTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Schedule-start notification plan")
struct ScheduleStartNotificationPlanTests {
    private func snapshot(
        id: UUID = UUID(), name: String = "Work Time",
        kind: RuleKind = .schedule, start: Int, end: Int = 0,
        days: Set<Weekday>, enabled: Bool = true, hasApps: Bool = true
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(
            id: id, name: name, kindRaw: kind.rawValue, isEnabled: enabled,
            hardMode: false, blockAdultContent: false, selectionModeRaw: "block",
            selectionData: hasApps ? Data([1]) : nil,
            dayNumbers: days.map(\.rawValue), startMinutes: start, endMinutes: end,
            dailyLimitMinutes: 0, maxOpens: 0, pausedUntil: nil)
    }

    @Test("A single-day rule fires 5 minutes before the window starts, same weekday")
    func singleDay() {
        let id = UUID()
        let reqs = ScheduleStartNotificationPlan.requests(
            for: [snapshot(id: id, start: 9 * 60, end: 17 * 60, days: [.monday])])
        #expect(reqs.count == 1)
        let req = reqs[0]
        #expect(req.identifier == NotificationIDs.scheduleStart(ruleID: id, weekday: .monday))
        #expect(req.dateComponents.weekday == Weekday.monday.rawValue)  // 2
        #expect(req.dateComponents.hour == 8)
        #expect(req.dateComponents.minute == 55)
        #expect(req.body == "Work Time starts in 5 minutes.")
    }

    @Test("A start within the lead time rolls the warning back to the previous weekday")
    func rollsOverToPreviousDay() {
        let id = UUID()
        // 00:02 Monday → 23:57 Sunday.
        let reqs = ScheduleStartNotificationPlan.requests(
            for: [snapshot(id: id, start: 2, end: 8 * 60, days: [.monday])])
        #expect(reqs.count == 1)
        #expect(reqs[0].identifier == NotificationIDs.scheduleStart(ruleID: id, weekday: .sunday))
        #expect(reqs[0].dateComponents.weekday == Weekday.sunday.rawValue)  // 1
        #expect(reqs[0].dateComponents.hour == 23)
        #expect(reqs[0].dateComponents.minute == 57)
    }

    @Test("Sunday wraps back to Saturday on rollover")
    func sundayWrapsToSaturday() {
        let reqs = ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 2, end: 8 * 60, days: [.sunday])])
        #expect(reqs.count == 1)
        #expect(reqs[0].dateComponents.weekday == Weekday.saturday.rawValue)  // 7
        #expect(reqs[0].dateComponents.hour == 23)
        #expect(reqs[0].dateComponents.minute == 57)
    }

    @Test("A multi-day rule emits one weekly request per enabled day, sorted")
    func multiDay() {
        let reqs = ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 9 * 60, end: 17 * 60, days: [.monday, .wednesday, .friday])])
        #expect(reqs.count == 3)
        #expect(reqs.map { $0.dateComponents.weekday } == [2, 4, 6])
        #expect(reqs.allSatisfy { $0.dateComponents.hour == 8 && $0.dateComponents.minute == 55 })
    }

    @Test("An every-day rule collapses to a single daily request (no weekday)")
    func everyDayCollapses() {
        let id = UUID()
        let reqs = ScheduleStartNotificationPlan.requests(
            for: [snapshot(id: id, start: 9 * 60, end: 17 * 60, days: Weekday.everyDay)])
        #expect(reqs.count == 1)
        #expect(reqs[0].identifier == NotificationIDs.scheduleStartDaily(ruleID: id))
        #expect(reqs[0].dateComponents.weekday == nil)
        #expect(reqs[0].dateComponents.hour == 8)
        #expect(reqs[0].dateComponents.minute == 55)
    }

    @Test("Ineligible rules produce no requests")
    func exclusions() {
        // Disabled.
        #expect(ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 9 * 60, end: 17 * 60, days: [.monday], enabled: false)]).isEmpty)
        // No enabled days.
        #expect(ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 9 * 60, end: 17 * 60, days: [])]).isEmpty)
        // No apps selected.
        #expect(ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 9 * 60, end: 17 * 60, days: [.monday], hasApps: false)]).isEmpty)
        // 24-hour window (start == end): never "starts".
        #expect(ScheduleStartNotificationPlan.requests(
            for: [snapshot(start: 0, end: 0, days: [.monday])]).isEmpty)
        // Not a schedule rule.
        #expect(ScheduleStartNotificationPlan.requests(
            for: [snapshot(kind: .timeLimit, start: 9 * 60, end: 17 * 60, days: [.monday])]).isEmpty)
    }
}
