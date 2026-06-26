//
//  RuleSchedulerWarnTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Rule scheduler → time-limit warn activity")
struct RuleSchedulerWarnTests {
    private func freshDefaults(timeLimitNotify: Bool) -> UserDefaults {
        let name = "warn-scheduler-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if timeLimitNotify {
            defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
            defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        }
        return defaults
    }

    private func makeScheduler(defaults: UserDefaults) -> (RuleScheduler, MockActivityMonitor) {
        let monitor = MockActivityMonitor()
        let scheduler = RuleScheduler(
            monitor: monitor, snapshots: RuleSnapshotUserDefaultsStore(defaults: defaults), defaults: defaults)
        return (scheduler, monitor)
    }

    private func timeLimitRule(limit: Int) throws -> BlockingRule {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Apps", selectionData: Data([1]), selectionCount: 1)
        let rule = BlockingRule(
            name: "Social", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: limit)),
            days: Weekday.everyDay)
        context.insert(list)
        context.insert(rule)
        rule.appList = list
        return rule
    }

    @Test("Opted-in time limit registers a separate warn activity 5 min before the budget")
    func registersWarnActivityWhenEnabled() throws {
        let defaults = freshDefaults(timeLimitNotify: true)
        let (scheduler, monitor) = makeScheduler(defaults: defaults)
        let rule = try timeLimitRule(limit: 60)

        scheduler.sync(rules: [rule])

        let blockName = MonitoringPlan.dailyActivityName(for: rule.id)
        let warnName = MonitoringPlan.warnActivityName(for: rule.id)
        #expect(monitor.monitoredNames.contains(blockName))
        #expect(monitor.monitoredNames.contains(warnName))
        // Warn fires at budget − 5.
        #expect(monitor.startedEvents[warnName]?["warn-55"] == 55)
        // The enforcement activity still carries only its block event.
        #expect(monitor.startedEvents[blockName]?[MonitoringPlan.minuteEventName(for: 60)] == 60)
    }

    @Test("No warn activity when the nudge is off")
    func noWarnActivityWhenDisabled() throws {
        let defaults = freshDefaults(timeLimitNotify: false)
        let (scheduler, monitor) = makeScheduler(defaults: defaults)
        let rule = try timeLimitRule(limit: 60)

        scheduler.sync(rules: [rule])

        #expect(monitor.monitoredNames.contains(MonitoringPlan.dailyActivityName(for: rule.id)))
        #expect(!monitor.monitoredNames.contains(MonitoringPlan.warnActivityName(for: rule.id)))
    }

    @Test("No warn activity when the budget is at or below the lead time")
    func noWarnActivityForTinyBudget() throws {
        let defaults = freshDefaults(timeLimitNotify: true)
        let (scheduler, monitor) = makeScheduler(defaults: defaults)
        let rule = try timeLimitRule(limit: 5)

        scheduler.sync(rules: [rule])

        #expect(!monitor.monitoredNames.contains(MonitoringPlan.warnActivityName(for: rule.id)))
    }

    @Test("Toggling the nudge on adds/removes the warn activity without restarting the block")
    func togglingNudgeLeavesBlockActivityUntouched() throws {
        let defaults = freshDefaults(timeLimitNotify: false)
        let (scheduler, monitor) = makeScheduler(defaults: defaults)
        let rule = try timeLimitRule(limit: 60)
        let blockName = MonitoringPlan.dailyActivityName(for: rule.id)
        let warnName = MonitoringPlan.warnActivityName(for: rule.id)

        // Nudge off: only the block activity starts (one start call).
        scheduler.sync(rules: [rule])
        #expect(monitor.startCallCount == 1)
        #expect(!monitor.monitoredNames.contains(warnName))

        // Turn the nudge on and re-sync: warn activity is added (one more start),
        // block activity is NOT restarted (would be a third start).
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
        defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        scheduler.sync(rules: [rule])
        #expect(monitor.startCallCount == 2)
        #expect(monitor.monitoredNames.contains(blockName))
        #expect(monitor.monitoredNames.contains(warnName))

        // Turn it back off: warn activity is stopped, block still present and
        // never restarted (start count unchanged).
        defaults.set(false, forKey: AppGroup.notifyTimeLimitEndingKey)
        scheduler.sync(rules: [rule])
        #expect(monitor.startCallCount == 2)
        #expect(monitor.monitoredNames.contains(blockName))
        #expect(!monitor.monitoredNames.contains(warnName))
    }
}
