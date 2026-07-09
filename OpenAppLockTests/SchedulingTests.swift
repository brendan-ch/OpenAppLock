//
//  SchedulingTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

private func freshDefaults() -> UserDefaults {
    let name = "scheduling-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("Rule snapshots")
struct RuleSnapshotTests {
    @Test("Snapshots round-trip through the shared store")
    func storeRoundTrip() throws {
        let store = RuleSnapshotUserDefaultsStore(defaults: freshDefaults())
        let snapshot = RuleSnapshotDTO(
            id: UUID(), name: "Time Keeper", kindRaw: "timeLimit", isEnabled: true,
            hardMode: false, selectionModeRaw: "block",
            selectionData: Data([1]), dayNumbers: [2, 3], startMinutes: 540, endMinutes: 1020,
            dailyLimitMinutes: 45, maxOpens: 5, pausedUntil: nil
        )
        store.save([snapshot])
        #expect(store.load() == [snapshot])
        #expect(store.snapshot(for: snapshot.id) == snapshot)
        #expect(store.snapshot(for: snapshot.id)?.startMinutes == 540)
        #expect(store.snapshot(for: snapshot.id)?.endMinutes == 1020)
        #expect(store.snapshot(for: UUID()) == nil)
    }

    @Test("Snapshots mirror rules and their app lists")
    func mirrorsRule() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions", selectionData: Data([9]), selectionCount: 1)
        let rule = BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: 3)),
            days: Weekday.weekends)
        context.insert(list)
        context.insert(rule)
        rule.appList = list

        let snapshot = RuleSnapshotDTO(rule: rule)
        #expect(snapshot.id == rule.id)
        #expect(snapshot.kind == .openLimit)
        #expect(snapshot.selectionData == Data([9]))
        #expect(snapshot.days == Weekday.weekends)
        #expect(snapshot.maxOpens == 3)
        #expect(snapshot.startMinutes == rule.startMinutes)
        #expect(snapshot.endMinutes == rule.endMinutes)
    }

    @Test("Snapshots saved before the window fields decode with a zeroed window")
    func decodesLegacySnapshotWithoutWindowFields() throws {
        // A blob shaped like a pre-schedule-window snapshot: no start/endMinutes.
        let id = UUID()
        let legacy = """
            [{"id":"\(id.uuidString)","name":"Old","kindRaw":"timeLimit","isEnabled":true,\
            "hardMode":false,"selectionModeRaw":"block",\
            "dayNumbers":[2,3],"dailyLimitMinutes":45,"maxOpens":5}]
            """
        let defaults = freshDefaults()
        defaults.set(Data(legacy.utf8), forKey: "ruleSnapshots")
        let store = RuleSnapshotUserDefaultsStore(defaults: defaults)

        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == id)
        #expect(loaded.first?.startMinutes == 0)
        #expect(loaded.first?.endMinutes == 0)
        #expect(loaded.first?.dailyLimitMinutes == 45)
    }
}

@MainActor
@Suite("Monitoring plan")
struct MonitoringPlanTests {
    @Test("Activity names round-trip rule IDs, with and without a day key")
    func nameRoundTrip() {
        let id = UUID()
        let dayKey = "2026-06-29"
        let dayKeyed = MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)
        #expect(dayKeyed == "rule-\(id.uuidString)-2026-06-29")
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: dayKeyed) == id)
        #expect(MonitoringPlan.dayKey(fromActivityName: dayKeyed) == dayKey)
        // The legacy, un-keyed form (open-limit / pre-upgrade) still parses…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: "rule-\(id.uuidString)") == id)
        // …and reports no day key.
        #expect(MonitoringPlan.dayKey(fromActivityName: "rule-\(id.uuidString)") == nil)
        // Session names and garbage are not daily activities.
        #expect(
            MonitoringPlan.ruleID(
                fromSessionActivityName: MonitoringPlan.sessionActivityName(for: id)) == id)
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: "garbage") == nil)
        #expect(
            MonitoringPlan.ruleID(
                fromSessionActivityName: MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)) == nil)
    }

    @Test("Schedule-window activity names round-trip rule IDs")
    func scheduleWindowNameRoundTrip() {
        let id = UUID()
        let primary = MonitoringPlan.scheduleWindowName(for: id)
        let late = MonitoringPlan.scheduleWindowLateName(for: id)
        #expect(primary != late)
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: primary) == id)
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: late) == id)
        // Daily / session / garbage names are not schedule-window names.
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: MonitoringPlan.dailyActivityName(for: id)) == nil)
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: "garbage") == nil)
        // Schedule-window names are not mistaken for daily activities.
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: primary) == nil)
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: late) == nil)
    }

    @Test("A time limit registers a single block event at the budget")
    func blockEvent() {
        let events = MonitoringPlan.blockEvent(forLimit: 45)
        #expect(events.count == 1)
        #expect(events[MonitoringPlan.minuteEventName(for: 45)] == 45)
        #expect(
            MonitoringPlan.minutes(fromEventName: MonitoringPlan.minuteEventName(for: 45)) == 45)
        #expect(MonitoringPlan.minutes(fromEventName: "nope") == nil)
    }
}

@MainActor
@Suite("Rule scheduler → DeviceActivity")
struct RuleSchedulerTests {
    private func makeScheduler() -> (RuleScheduler, MockActivityMonitor, RuleSnapshotUserDefaultsStore) {
        let monitor = MockActivityMonitor()
        let store = RuleSnapshotUserDefaultsStore(defaults: freshDefaults())
        return (RuleScheduler(monitor: monitor, snapshots: store), monitor, store)
    }

    private func limitRule(kind: RuleKind, name: String) throws -> BlockingRule {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Apps", selectionData: Data([1]), selectionCount: 1)
        let rule = BlockingRule(
            name: name, configuration: .default(for: kind), days: Weekday.everyDay)
        context.insert(list)
        context.insert(rule)
        rule.appList = list
        return rule
    }

    private func scheduleRule(
        name: String, start: Int, end: Int, days: Set<Weekday> = Weekday.everyDay,
        withApps: Bool = true
    ) throws -> BlockingRule {
        let context = try makeInMemoryContext()
        let rule = BlockingRule(
            name: name,
            configuration: .schedule(ScheduleConfig(startMinutes: start, endMinutes: end)),
            days: days)
        context.insert(rule)
        if withApps {
            let list = AppList(name: "Apps", selectionData: Data([7]), selectionCount: 1)
            context.insert(list)
            rule.appList = list
        }
        return rule
    }

    @Test("startDayMonitoring records a dated, event-carrying window on the mock")
    func mockRecordsDayMonitoring() throws {
        let monitor = MockActivityMonitor()
        let from = date(2025, 1, 6)
        let to = date(2025, 1, 7)
        try monitor.startDayMonitoring(
            name: "rule-x-2025-01-06", from: from, to: to,
            selectionData: Data([1]), eventMinutes: ["minutes-45": 45])

        #expect(monitor.monitoredNames.contains("rule-x-2025-01-06"))
        #expect(monitor.startedEvents["rule-x-2025-01-06"]?["minutes-45"] == 45)
        #expect(monitor.startedDayWindows["rule-x-2025-01-06"]?.from == from)
        #expect(monitor.startedDayWindows["rule-x-2025-01-06"]?.to == to)
    }

    @Test("A time limit arms a per-day block activity for today and tomorrow")
    func timeLimitArmsTwoDayKeyedActivities() throws {
        let (scheduler, monitor, store) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)

        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)

        let today = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))
        let tomorrow = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 7), calendar: utc))
        #expect(monitor.monitoredNames.contains(today))
        #expect(monitor.monitoredNames.contains(tomorrow))
        #expect(
            monitor.startedEvents[today]?[MonitoringPlan.minuteEventName(for: rule.dailyLimitMinutes)]
                == rule.dailyLimitMinutes)
        // No legacy un-keyed daily activity is armed for a time limit.
        #expect(!monitor.monitoredNames.contains("rule-\(rule.id.uuidString)"))
        #expect(store.snapshot(for: rule.id) != nil)
    }

    @Test("Rolling the day forward arms the new day and reaps the day that fell out of the horizon")
    func dayRolloverReapsPastActivity() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")

        scheduler.sync(snapshots: [rule.dto], at: date(2025, 1, 6, 10, 0), calendar: utc)  // arms 01-06, 01-07
        scheduler.sync(snapshots: [rule.dto], at: date(2025, 1, 7, 10, 0), calendar: utc)  // arms 01-07, 01-08

        let jan6 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))
        let jan8 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 8), calendar: utc))
        #expect(!monitor.monitoredNames.contains(jan6))   // reaped
        #expect(monitor.monitoredNames.contains(jan8))    // newly armed
    }

    @Test("A background self-armed activity is adopted, not restarted, by the next sync")
    func adoptsSelfArmedActivity() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)
        let todayName = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))

        // Simulate the monitor having self-armed today's activity in the
        // background: it is monitored, but the scheduler recorded no fingerprint.
        try monitor.startDayMonitoring(
            name: todayName, from: date(2025, 1, 6), to: date(2025, 1, 7),
            selectionData: Data([1]),
            eventMinutes: MonitoringPlan.blockEvent(forLimit: rule.dailyLimitMinutes))
        let startsAfterSelfArm = monitor.startCallCount  // 1

        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)
        // Today's activity is adopted (not restarted → its live count is kept);
        // only tomorrow's is newly armed.
        #expect(monitor.startCallCount == startsAfterSelfArm + 1)

        // A second sync also leaves today's alone (its fingerprint was recorded).
        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)
        #expect(monitor.startCallCount == startsAfterSelfArm + 1)
    }

    @Test("Open-limit rules monitor the day without usage checkpoints")
    func openLimitHasNoCheckpoints() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .openLimit, name: "Gate Keeper")

        scheduler.sync(snapshots: [rule.dto])

        #expect(monitor.startedEvents[MonitoringPlan.dailyActivityName(for: rule.id)]?.isEmpty == true)
    }

    @Test("App-less rules (schedule or limit) are not monitored")
    func skipsUnmonitorable() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let context = try makeInMemoryContext()
        let applessSchedule = BlockingRule(name: "Work Time")
        let applessLimit = BlockingRule(name: "Empty", configuration: .timeLimit(TimeLimitConfig()))
        context.insert(applessSchedule)
        context.insert(applessLimit)

        scheduler.sync(snapshots: [applessSchedule.dto, applessLimit.dto])

        #expect(monitor.monitoredNames.isEmpty)
    }

    @Test("A non-crossing schedule rule registers one window activity")
    func schedulesNonCrossingWindow() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)

        scheduler.sync(snapshots: [rule.dto])

        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        #expect(monitor.monitoredNames == [primary])
        #expect(monitor.startedWindows[primary]?.start == 9 * 60)
        #expect(monitor.startedWindows[primary]?.end == 17 * 60)
        // A schedule window carries no usage-threshold events.
        #expect(monitor.startedEvents[primary] == nil)
    }

    @Test("A dayless schedule rule is not monitored")
    func skipsDaylessSchedule() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "No Days", start: 9 * 60, end: 17 * 60, days: [])

        scheduler.sync(snapshots: [rule.dto])

        #expect(monitor.monitoredNames.isEmpty)
    }

    @Test("A midnight-crossing schedule rule registers two window activities")
    func schedulesCrossingWindow() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Deep Sleep", start: 22 * 60, end: 6 * 60)

        scheduler.sync(snapshots: [rule.dto])

        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        let late = MonitoringPlan.scheduleWindowLateName(for: rule.id)
        #expect(Set(monitor.monitoredNames) == [primary, late])
        // The evening half runs to the end of the day; the morning half from midnight.
        #expect(monitor.startedWindows[primary]?.start == 22 * 60)
        #expect(monitor.startedWindows[primary]?.end == 24 * 60 - 1)
        #expect(monitor.startedWindows[late]?.start == 0)
        #expect(monitor.startedWindows[late]?.end == 6 * 60)
    }

    @Test("A window ending exactly at midnight registers a single evening activity")
    func scheduleWindowEndingAtMidnight() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Late", start: 22 * 60, end: 0)

        scheduler.sync(snapshots: [rule.dto])

        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        let late = MonitoringPlan.scheduleWindowLateName(for: rule.id)
        #expect(monitor.monitoredNames == [primary])
        #expect(monitor.startedWindows[primary]?.start == 22 * 60)
        #expect(monitor.startedWindows[primary]?.end == 24 * 60 - 1)
        #expect(monitor.startedWindows[late] == nil)
    }

    @Test("A 24-hour window registers a single all-day activity")
    func scheduleFullDayWindow() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Always", start: 0, end: 0)

        scheduler.sync(snapshots: [rule.dto])

        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        #expect(monitor.monitoredNames == [primary])
        #expect(monitor.startedWindows[primary]?.start == 0)
        #expect(monitor.startedWindows[primary]?.end == 24 * 60 - 1)
    }

    @Test("Switching a window from crossing to non-crossing stops the morning half")
    func dropsLateActivityWhenWindowStopsCrossing() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Deep Sleep", start: 22 * 60, end: 6 * 60)
        scheduler.sync(snapshots: [rule.dto])

        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        let late = MonitoringPlan.scheduleWindowLateName(for: rule.id)
        #expect(Set(monitor.monitoredNames) == [primary, late])

        // Now a normal daytime window — the post-midnight half must be stopped.
        rule.startMinutes = 9 * 60
        rule.endMinutes = 17 * 60
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.monitoredNames == [primary])
        #expect(monitor.startedWindows[late] == nil)
    }

    @Test("Changing only the days does not restart the window activity")
    func keepsWindowWhenOnlyDaysChange() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(
            name: "Work Time", start: 9 * 60, end: 17 * 60, days: Weekday.weekdays)

        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.startCallCount == 1)

        // The window interval is unchanged, so the DeviceActivity activity that
        // only encodes start/end need not restart — reconcile() reads days fresh.
        rule.days = Weekday.everyDay
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.startCallCount == 1)
    }

    @Test("Disabling a schedule rule stops its window monitoring")
    func stopsScheduleWindowWhenDisabled() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)

        scheduler.sync(snapshots: [rule.dto])
        #expect(!monitor.monitoredNames.isEmpty)

        rule.isEnabled = false
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.monitoredNames.isEmpty)
    }

    @Test("Changing a schedule window restarts monitoring")
    func restartsOnWindowChange() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)

        scheduler.sync(snapshots: [rule.dto])
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.startCallCount == 1)

        rule.endMinutes = 18 * 60
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.startCallCount == 2)
        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        #expect(monitor.startedWindows[primary]?.end == 18 * 60)
    }

    @Test("Monitoring stops when a rule is disabled or removed")
    func stopsStaleMonitoring() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        scheduler.sync(snapshots: [rule.dto])

        rule.isEnabled = false
        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.monitoredNames.isEmpty)

        rule.isEnabled = true
        scheduler.sync(snapshots: [rule.dto])
        scheduler.sync(snapshots: [])
        #expect(monitor.monitoredNames.isEmpty)
    }

    @Test("Unchanged rules are not restarted (checkpoints would reset)")
    func avoidsRestartChurn() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)

        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)
        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)
        #expect(monitor.startCallCount == 2)  // today + tomorrow, each started once

        rule.dailyLimitMinutes = 60
        scheduler.sync(snapshots: [rule.dto], at: now, calendar: utc)
        #expect(monitor.startCallCount == 4)  // both day activities restart on budget change
    }

    @Test("Selection fingerprint is a deterministic SHA-256, stable across launches")
    func selectionFingerprintIsProcessStable() {
        // `Data.hashValue` is seeded randomly per process, so using it in the
        // limit-activity fingerprint restarted every daily activity on each
        // launch (resetting threshold accounting). SHA-256 is fixed, so the
        // fingerprint can be asserted against a constant — a value that random
        // per-process hashing could never satisfy.
        #expect(
            RuleScheduler.selectionFingerprint(Data([1]))
                == "4bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459a")
    }

    @Test("scheduleResumeReArm starts a one-shot pause activity padded one minute past the pause")
    func schedulesPauseReArm() {
        let (scheduler, monitor, _) = makeScheduler()
        let id = UUID()
        scheduler.scheduleResumeReArm(
            for: id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        let name = MonitoringPlan.pauseActivityName(for: id)
        #expect(monitor.monitoredNames.contains(name))
        #expect(monitor.startedOneShots[name]?.end == date(2025, 1, 6, 10, 16))  // +1 padding
    }

    @Test("cancelResumeReArm stops the pause activity")
    func cancelsPauseReArm() {
        let (scheduler, monitor, _) = makeScheduler()
        let id = UUID()
        scheduler.scheduleResumeReArm(
            for: id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        scheduler.cancelResumeReArm(for: id)
        #expect(!monitor.monitoredNames.contains(MonitoringPlan.pauseActivityName(for: id)))
    }

    @Test("sync reaps a pause re-arm whose rule is no longer paused")
    func reapsStalePauseReArm() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)
        scheduler.scheduleResumeReArm(
            for: rule.id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(monitor.monitoredNames.contains(pauseName))

        scheduler.sync(snapshots: [rule.dto])  // rule.pausedUntil == nil → reaped
        #expect(!monitor.monitoredNames.contains(pauseName))
    }

    @Test("sync keeps a pause re-arm for a still-paused rule")
    func keepsActivePauseReArm() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)
        rule.pausedUntil = date(2025, 1, 6, 10, 15)
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)
        scheduler.scheduleResumeReArm(
            for: rule.id, until: rule.pausedUntil!,
            now: date(2025, 1, 6, 10, 0), calendar: utc)

        scheduler.sync(snapshots: [rule.dto])
        #expect(monitor.monitoredNames.contains(pauseName))
    }

    @Test("sync reaps a pause re-arm for a rule that no longer exists")
    func reapsPauseReArmForDeletedRule() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)
        scheduler.scheduleResumeReArm(
            for: rule.id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(monitor.monitoredNames.contains(pauseName))

        // The rule is gone from the sync set (deleted mid-pause) → reaped.
        scheduler.sync(snapshots: [])
        #expect(!monitor.monitoredNames.contains(pauseName))
    }
}

@MainActor
@Suite("Limit enforcement reactions")
struct LimitEnforcementTests {
    let monday = date(2025, 1, 6, 10, 0)

    private func makeEnforcement() -> (LimitEnforcement, MockShieldController, UsageLedger, RuleSnapshotUserDefaultsStore) {
        let shields = MockShieldController()
        let ledger = UsageLedger(defaults: freshDefaults())
        let store = RuleSnapshotUserDefaultsStore(defaults: freshDefaults())
        // Isolated session store so granted-open writes don't touch the app group.
        return (
            LimitEnforcement(
                snapshots: store, ledger: ledger, shields: shields,
                sessions: OpenSessionStore(defaults: freshDefaults()),
                dayStarts: DayStartStore(defaults: freshDefaults())),
            shields, ledger, store)
    }

    private func snapshot(
        kind: RuleKind, limit: Int = 45, maxOpens: Int = 5,
        days: Set<Weekday> = Weekday.everyDay, pausedUntil: Date? = nil
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(
            id: UUID(), name: "Rule", kindRaw: kind.rawValue, isEnabled: true,
            hardMode: false, selectionModeRaw: "block",
            selectionData: Data([1]), dayNumbers: days.map(\.rawValue),
            startMinutes: 0, endMinutes: 0,
            dailyLimitMinutes: limit, maxOpens: maxOpens, pausedUntil: pausedUntil
        )
    }

    @Test("An ineligible rule does not accrue usage from a checkpoint")
    func ineligibleRuleDoesNotAccrue() {
        let (enforcement, _, ledger, store) = makeEnforcement()
        // Weekday-only rule; a checkpoint arrives on a Saturday (not scheduled).
        let snap = snapshot(kind: .timeLimit, days: Weekday.weekdays)
        store.save([snap])
        let saturday = date(2025, 1, 11, 10, 0) // 2025-01-11 is a Saturday

        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: saturday, calendar: utc)

        #expect(
            ledger.usage(for: snap.id, onDayContaining: saturday, calendar: utc).minutesUsed == 0)
    }

    @Test("Day start shields open-limit rules so opens can be counted")
    func dayStartShieldsOpenLimit() {
        let (enforcement, shields, _, store) = makeEnforcement()
        let snap = snapshot(kind: .openLimit)
        store.save([snap])

        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("Day start clears time-limit shields for the fresh budget")
    func dayStartClearsTimeLimit() {
        let (enforcement, shields, _, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit)
        store.save([snap])
        shields.applyShield(
            ruleID: snap.id, selectionData: nil, mode: .block)

        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Usage checkpoints record minutes and shield at the limit")
    func usageCheckpointsShieldAtLimit() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)

        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 20)
        #expect(shields.shieldedRuleIDs.isEmpty)

        enforcement.handleUsageMinutes(45, ruleID: snap.id, now: monday, calendar: utc)
        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("A stale checkpoint exceeding today's elapsed minutes is ignored")
    func staleCrossMidnightCheckpointIgnored() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])

        // 00:30 — only 30 minutes have elapsed since midnight, so a 45-minute
        // cumulative checkpoint can only be yesterday's spent budget delivered
        // late across midnight. It must not be recorded as today's usage, and
        // must not re-shield apps the user hasn't touched today.
        let earlyMorning = date(2025, 1, 6, 0, 30)
        enforcement.handleDayStart(ruleID: snap.id, now: earlyMorning, calendar: utc)
        enforcement.handleUsageMinutes(45, ruleID: snap.id, now: earlyMorning, calendar: utc)

        #expect(
            ledger.usage(for: snap.id, onDayContaining: earlyMorning, calendar: utc).minutesUsed == 0)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("A checkpoint within today's elapsed time still records and shields")
    func freshCheckpointWithinElapsedHonoured() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])

        // 00:45 — 45 minutes have elapsed, so a 45-minute checkpoint is
        // physically possible today and must be honoured (boundary case).
        let quarterToOne = date(2025, 1, 6, 0, 45)
        enforcement.handleDayStart(ruleID: snap.id, now: quarterToOne, calendar: utc)
        enforcement.handleUsageMinutes(45, ruleID: snap.id, now: quarterToOne, calendar: utc)

        #expect(
            ledger.usage(for: snap.id, onDayContaining: quarterToOne, calendar: utc).minutesUsed == 45)
        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("A usage checkpoint tagged with a prior day key is dropped (cross-midnight flush)")
    func staleDayKeyedCheckpointDropped() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 30)
        store.save([snap])
        // It is 2025-01-07 01:33; today's interval has started…
        let today = date(2025, 1, 7, 1, 33)
        enforcement.handleDayStart(ruleID: snap.id, now: today, calendar: utc)
        // …but the budget event is tagged with YESTERDAY (2025-01-06): a flush.
        enforcement.handleUsageMinutes(
            30, ruleID: snap.id, activityDayKey: "2025-01-06", now: today, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: today, calendar: utc).minutesUsed == 0)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("A usage checkpoint tagged with today's day key still records and shields")
    func todayDayKeyedCheckpointHonoured() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 30)
        store.save([snap])
        let today = date(2025, 1, 6, 10, 0)
        enforcement.handleDayStart(ruleID: snap.id, now: today, calendar: utc)
        enforcement.handleUsageMinutes(
            30, ruleID: snap.id, activityDayKey: "2025-01-06", now: today, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: today, calendar: utc).minutesUsed == 30)
        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("A checkpoint before a confirmed day-start is dropped")
    func checkpointBeforeConfirmedStartDropped() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])
        // No handleDayStart → no confirmed start for today, so the event is a
        // pre-boundary residual and must be dropped.
        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: monday, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 0)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Day start zeroes today's time-limit ledger once, only on a transition")
    func dayStartZeroesOnceOnTransition() {
        let (enforcement, _, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit)
        store.save([snap])
        // A stale value sitting in today's key (e.g. a pre-boundary write).
        ledger.setUsage(
            RuleUsageDTO(minutesUsed: 45), for: snap.id, onDayContaining: monday, calendar: utc)

        // First day-start of the day: transition → zeroed.
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 0)

        // A legitimate accrual after the transition...
        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 20)

        // ...survives a spurious same-day re-fire (no second zero).
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 20)
    }

    @Test("An Open press spends one open and lifts the shield")
    func openRequestSpendsAndLifts() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .openLimit, maxOpens: 2)
        store.save([snap])
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)

        #expect(enforcement.handleOpenRequest(ruleID: snap.id, now: monday, calendar: utc))
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).opensUsed == 1)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Open presses are refused once opens are exhausted")
    func openRequestRefusedWhenExhausted() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .openLimit, maxOpens: 1)
        store.save([snap])
        ledger.recordOpen(for: snap.id, onDayContaining: monday, calendar: utc)
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)

        #expect(!enforcement.handleOpenRequest(ruleID: snap.id, now: monday, calendar: utc))
        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("Granting an open records a session marker; ending it clears it")
    func openSessionMarkerLifecycle() {
        let shields = MockShieldController()
        let ledger = UsageLedger(defaults: freshDefaults())
        let store = RuleSnapshotUserDefaultsStore(defaults: freshDefaults())
        let sessions = OpenSessionStore(defaults: freshDefaults())
        let enforcement = LimitEnforcement(
            snapshots: store, ledger: ledger, shields: shields, sessions: sessions)
        let snap = snapshot(kind: .openLimit, maxOpens: 3)
        store.save([snap])

        #expect(!sessions.hasActiveSession(for: snap.id, at: monday))
        #expect(enforcement.handleOpenRequest(ruleID: snap.id, now: monday, calendar: utc))
        // The granted ~15-minute session is now recorded and live...
        #expect(sessions.hasActiveSession(for: snap.id, at: monday))
        // ...but expires after the session length.
        #expect(!sessions.hasActiveSession(for: snap.id, at: date(2025, 1, 6, 10, 17)))

        enforcement.handleOpenSessionEnded(ruleID: snap.id, now: monday, calendar: utc)
        #expect(!sessions.hasActiveSession(for: snap.id, at: monday))
    }

    @Test("Session end re-shields the rule for the next open")
    func sessionEndReshields() {
        let (enforcement, shields, _, store) = makeEnforcement()
        let snap = snapshot(kind: .openLimit)
        store.save([snap])

        enforcement.handleOpenSessionEnded(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("A paused (unblocked) rule is left alone until midnight")
    func pausedRuleLeftAlone() {
        let (enforcement, shields, _, store) = makeEnforcement()
        let snap = snapshot(kind: .openLimit, pausedUntil: date(2025, 1, 7, 0, 0))
        store.save([snap])

        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
        enforcement.handleOpenSessionEnded(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("handlePauseEnded re-shields a spent, eligible time-limit rule")
    func pauseEndedReshieldsSpentTimeLimit() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])
        ledger.setUsage(
            RuleUsageDTO(minutesUsed: 45), for: snap.id, onDayContaining: monday, calendar: utc)

        enforcement.handlePauseEnded(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("handlePauseEnded clears the shield while the pause is still in effect")
    func pauseEndedClearsWhilePaused() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45, pausedUntil: date(2025, 1, 6, 10, 15))
        store.save([snap])
        ledger.setUsage(
            RuleUsageDTO(minutesUsed: 45), for: snap.id, onDayContaining: monday, calendar: utc)
        shields.applyShield(ruleID: snap.id, selectionData: nil, mode: .block)

        // monday (10:00) is before pausedUntil (10:15), so the pause is still active.
        enforcement.handlePauseEnded(ruleID: snap.id, now: monday, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }
}

@MainActor
@Suite("Schedule-window enforcement reactions")
struct ScheduleEnforcementTests {
    /// Monday 2025-01-06 10:00 UTC sits inside a 09:00–17:00 weekday window.
    let mondayMorning = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    private func makeEnforcement() -> (ScheduleEnforcement, MockShieldController, RuleSnapshotUserDefaultsStore) {
        let shields = MockShieldController()
        let store = RuleSnapshotUserDefaultsStore(defaults: freshDefaults())
        return (ScheduleEnforcement(snapshots: store, shields: shields), shields, store)
    }

    private func snapshot(
        start: Int = 9 * 60, end: Int = 17 * 60, days: Set<Weekday> = Weekday.everyDay,
        isEnabled: Bool = true, mode: SelectionMode = .block, pausedUntil: Date? = nil
    ) -> RuleSnapshotDTO {
        RuleSnapshotDTO(
            id: UUID(), name: "Work Time", kindRaw: RuleKind.schedule.rawValue,
            isEnabled: isEnabled, hardMode: false,
            selectionModeRaw: mode.rawValue, selectionData: Data([1]),
            dayNumbers: days.map(\.rawValue), startMinutes: start, endMinutes: end,
            dailyLimitMinutes: 45, maxOpens: 5, pausedUntil: pausedUntil
        )
    }

    @Test("Reconcile shields a rule whose window is active now")
    func shieldsActiveWindow() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot()
        store.save([snap])

        enforcement.reconcile(ruleID: snap.id, now: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("Reconcile clears a rule whose window is over")
    func clearsInactiveWindow() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot()
        store.save([snap])
        shields.applyShield(
            ruleID: snap.id, selectionData: nil, mode: .block)

        enforcement.reconcile(ruleID: snap.id, now: mondayEvening, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Reconcile forwards the rule's selection mode")
    func forwardsSelectionMode() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot(mode: .allowOnly)
        store.save([snap])

        enforcement.reconcile(ruleID: snap.id, now: mondayMorning, calendar: utc)

        #expect(shields.appliedModes[snap.id] == .allowOnly)
    }

    @Test("A disabled schedule rule is never shielded")
    func skipsDisabled() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot(isEnabled: false)
        store.save([snap])

        enforcement.reconcile(ruleID: snap.id, now: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("A paused (unblocked) schedule rule is left clear")
    func skipsPaused() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot(pausedUntil: date(2025, 1, 6, 17, 0))
        store.save([snap])

        enforcement.reconcile(ruleID: snap.id, now: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("A midnight-crossing window is active in the early morning")
    func shieldsCrossingWindowAfterMidnight() {
        let (enforcement, shields, store) = makeEnforcement()
        // 22:00–06:00 every day; 02:00 belongs to the window that started the
        // previous evening (so the previous day must be enabled — it is).
        let snap = snapshot(start: 22 * 60, end: 6 * 60)
        store.save([snap])

        enforcement.reconcile(ruleID: snap.id, now: date(2025, 1, 6, 2, 0), calendar: utc)

        #expect(shields.shieldedRuleIDs == [snap.id])
    }

    @Test("A weekday window is inactive on the weekend")
    func clearsOnDisabledDay() {
        let (enforcement, shields, store) = makeEnforcement()
        let snap = snapshot(days: Weekday.weekdays)
        store.save([snap])
        // 2025-01-11 is a Saturday.
        enforcement.reconcile(ruleID: snap.id, now: date(2025, 1, 11, 10, 0), calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }
}

@MainActor
@Suite("Day-start store")
struct DayStartStoreTests {
    private func makeStore() -> DayStartStore {
        let name = "daystart-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return DayStartStore(defaults: defaults)
    }

    @Test("Confirmed start round-trips and is day-scoped")
    func roundTrip() {
        let store = makeStore()
        let id = UUID()
        let monday = date(2025, 1, 6, 10, 0)
        #expect(store.confirmedStart(for: id) == nil)
        #expect(!store.hasConfirmedStart(for: id, onDayContaining: monday, calendar: utc))

        store.setConfirmedStart(utc.startOfDay(for: monday), for: id)
        #expect(store.confirmedStart(for: id) == utc.startOfDay(for: monday))
        #expect(store.hasConfirmedStart(for: id, onDayContaining: monday, calendar: utc))
        // A different day is not confirmed.
        #expect(!store.hasConfirmedStart(for: id, onDayContaining: date(2025, 1, 7, 1, 0), calendar: utc))
    }
}
