//
//  RuleSchedulerPlanTests.swift
//  OpenAppLockTests
//
//  Direct unit tests for RuleScheduler's pure planning methods — the layer
//  that maps a rule to the DeviceActivity activities it should run, before any
//  monitor side effects. These assert the fingerprint strings and the
//  threshold-accounting flag, which the monitor-based tests cannot observe.
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Rule scheduler → activity planning")
struct RuleSchedulerPlanTests {
    private func freshDefaults(timeLimitNotify: Bool = false) -> UserDefaults {
        let name = "plan-scheduler-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if timeLimitNotify {
            defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
            defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        }
        return defaults
    }

    private func makeScheduler(timeLimitNotify: Bool = false) -> RuleScheduler {
        let defaults = freshDefaults(timeLimitNotify: timeLimitNotify)
        // The planning methods never touch the monitor, so a bare mock suffices.
        return RuleScheduler(
            monitor: MockActivityMonitor(),
            snapshots: RuleSnapshotUserDefaultsStore(defaults: defaults),
            defaults: defaults)
    }

    private func limitRule(kind: RuleKind) throws -> BlockingRule {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Apps", selectionData: Data([1]), selectionCount: 1)
        let rule = BlockingRule(
            name: "Limit", configuration: .default(for: kind), days: Weekday.everyDay)
        context.insert(list)
        context.insert(rule)
        rule.appList = list
        return rule
    }

    private func scheduleRule(start: Int, end: Int) throws -> BlockingRule {
        let context = try makeInMemoryContext()
        let rule = BlockingRule(
            name: "Schedule",
            configuration: .schedule(ScheduleConfig(startMinutes: start, endMinutes: end)),
            days: Weekday.everyDay)
        context.insert(rule)
        return rule
    }

    private func windowBounds(
        _ payload: RuleScheduler.PlannedActivity.Payload
    ) -> (start: Int, end: Int)? {
        guard case let .window(start, end) = payload else { return nil }
        return (start, end)
    }

    // MARK: limitPlan

    @Test("limitPlan for an open limit plans no usage events and flags no accounting risk")
    func limitPlanOpenLimit() throws {
        let scheduler = makeScheduler()
        let rule = try limitRule(kind: .openLimit)

        let plan = scheduler.limitPlan(for: rule.dto, selectionData: Data([1]))

        #expect(plan.resetsThresholdAccountingOnRestart == false)
        guard case let .daily(_, events) = plan.payload else {
            Issue.record("expected a .daily payload")
            return
        }
        #expect(events.isEmpty)
    }

    @Test("limitPlan fingerprint encodes kind/budget/selection and changes only when those do")
    func limitPlanFingerprintTracksConfiguration() throws {
        let scheduler = makeScheduler()
        let rule = try limitRule(kind: .openLimit)
        // `limitPlan` only ever runs for open limits (see its doc comment), so
        // this uses that kind — even though the fingerprint it locks below
        // still keys on `dailyLimitMinutes`, not `maxOpens`, the field that
        // actually drives an open limit's behavior. That mismatch is
        // pre-existing and out of scope here; this test only pins the current
        // fingerprint format against the 002ac19 regression.
        rule.dailyLimitMinutes = 45

        let fingerprint = scheduler.limitPlan(for: rule.dto, selectionData: Data([1])).fingerprint
        // Locked to the exact format so a per-process-unstable hash (the 002ac19
        // regression) cannot creep back in unnoticed.
        #expect(
            fingerprint == "\(rule.kindRaw)|45|" + RuleScheduler.selectionFingerprint(Data([1])))
        // Stable for an unchanged rule…
        #expect(scheduler.limitPlan(for: rule.dto, selectionData: Data([1])).fingerprint == fingerprint)
        // …and different once the budget changes.
        rule.dailyLimitMinutes = 60
        #expect(scheduler.limitPlan(for: rule.dto, selectionData: Data([1])).fingerprint != fingerprint)
    }

    // MARK: schedulePlans

    @Test("schedulePlans for a non-crossing window plans one window activity")
    func schedulePlansNonCrossing() throws {
        let scheduler = makeScheduler()
        let rule = try scheduleRule(start: 9 * 60, end: 17 * 60)

        let plans = scheduler.schedulePlans(for: rule.dto)

        #expect(plans.count == 1)
        let plan = try #require(plans.first)
        #expect(plan.name == MonitoringPlan.scheduleWindowName(for: rule.id))
        #expect(plan.fingerprint == "schedule|\(9 * 60)|\(17 * 60)")
        #expect(plan.resetsThresholdAccountingOnRestart == false)
        guard case let .window(start, end) = plan.payload else {
            Issue.record("expected a .window payload")
            return
        }
        #expect(start == 9 * 60)
        #expect(end == 17 * 60)
    }

    @Test("schedulePlans for a midnight-crossing window plans two distinct window activities")
    func schedulePlansCrossing() throws {
        let scheduler = makeScheduler()
        let rule = try scheduleRule(start: 22 * 60, end: 6 * 60)

        let plans = scheduler.schedulePlans(for: rule.dto)

        #expect(plans.count == 2)
        let boundsByName = Dictionary(uniqueKeysWithValues: plans.map { ($0.name, $0.payload) })
        // The evening half runs from the start to the end of the day…
        let evening = try #require(
            boundsByName[MonitoringPlan.scheduleWindowName(for: rule.id)].flatMap(windowBounds))
        #expect(evening.start == 22 * 60)
        #expect(evening.end == 24 * 60 - 1)
        // …and the morning half from midnight to the end.
        let morning = try #require(
            boundsByName[MonitoringPlan.scheduleWindowLateName(for: rule.id)].flatMap(windowBounds))
        #expect(morning.start == 0)
        #expect(morning.end == 6 * 60)
    }
}
