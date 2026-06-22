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
        let warn = MonitoringPlan.warnActivityName(for: id)
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: warn) == id)
        // The warn activity is not mistaken for the enforcement (daily) activity…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: warn) == nil)
        // …and vice-versa.
        #expect(
            MonitoringPlan.ruleID(
                fromWarnActivityName: MonitoringPlan.dailyActivityName(for: id)) == nil)
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
}
