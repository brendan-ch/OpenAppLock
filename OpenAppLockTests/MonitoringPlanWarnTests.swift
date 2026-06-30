//
//  MonitoringPlanWarnTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Monitoring plan — time-limit warn activity")
struct MonitoringPlanWarnTests {
    @Test("Warn activity names round-trip rule IDs and don't collide with the block activity")
    func warnNameRoundTrip() {
        let id = UUID()
        let dayKey = "2026-06-29"
        let warn = MonitoringPlan.warnActivityName(for: id, dayKey: dayKey)
        #expect(warn == "tlwarn-\(id.uuidString)-2026-06-29")
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: warn) == id)
        #expect(MonitoringPlan.dayKey(fromActivityName: warn) == dayKey)
        // The warn activity is not mistaken for the enforcement (daily) activity…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: warn) == nil)
        // …and vice-versa.
        #expect(
            MonitoringPlan.ruleID(
                fromWarnActivityName: MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)) == nil)
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: "garbage") == nil)
    }

    @Test("Warn event fires 5 minutes before the budget when the budget exceeds the lead")
    func warnEventForLargeBudget() {
        let events = MonitoringPlan.warnEvent(forLimit: 60)
        #expect(events?.count == 1)
        #expect(events?["warn-55"] == 55)
    }

    @Test("Warn event is nil when the budget is at or below the lead time")
    func warnEventForSmallBudget() {
        #expect(MonitoringPlan.warnEvent(forLimit: 5) == nil)
        #expect(MonitoringPlan.warnEvent(forLimit: 4) == nil)
        #expect(MonitoringPlan.warnEvent(forLimit: 1) == nil)
        // Exactly one over the lead is the smallest budget that warns (at 1 min).
        #expect(MonitoringPlan.warnEvent(forLimit: 6)?["warn-1"] == 1)
    }

    @Test("Pause activity names round-trip rule IDs and don't collide with other activities")
    func pauseNameRoundTrip() {
        let id = UUID()
        let pause = MonitoringPlan.pauseActivityName(for: id)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: pause) == id)
        // Not mistaken for the daily, schedule-window, or warn activities…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: pause) == nil)
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: pause) == nil)
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: pause) == nil)
        // …and their names are not mistaken for a pause activity.
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: MonitoringPlan.dailyActivityName(for: id, dayKey: "2026-06-29")) == nil)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: MonitoringPlan.scheduleWindowName(for: id)) == nil)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: "garbage") == nil)
        #expect(MonitoringPlan.temporaryPauseMinutes == 15)
    }
}
