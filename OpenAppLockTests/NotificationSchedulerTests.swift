//
//  NotificationSchedulerTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

private func freshDefaults() -> UserDefaults {
    let name = "notification-scheduler-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func scheduleSnapshot(
    id: UUID = UUID(), name: String = "Work Time", start: Int, end: Int = 17 * 60,
    days: Set<Weekday>, enabled: Bool = true, hasApps: Bool = true
) -> RuleSnapshotDTO {
    RuleSnapshotDTO(
        id: id, name: name, kindRaw: RuleKind.schedule.rawValue, isEnabled: enabled,
        hardMode: false, selectionModeRaw: "block",
        selectionData: hasApps ? Data([1]) : nil,
        dayNumbers: days.map(\.rawValue), startMinutes: start, endMinutes: end,
        dailyLimitMinutes: 0, maxOpens: 0, pausedUntil: nil)
}

@Suite("Notification scheduler reconciliation")
struct NotificationSchedulerTests {
    @Test("Enabled sync schedules the desired requests")
    func enabledAddsDesired() async {
        let center = MockNotificationScheduler()
        let scheduler = NotificationScheduler(center: center, defaults: freshDefaults())
        let id = UUID()

        await scheduler.sync(
            snapshots: [scheduleSnapshot(id: id, start: 9 * 60, days: Weekday.everyDay)],
            enabled: true)

        #expect(center.pending.count == 1)
        #expect(center.pending.first?.identifier == NotificationIDs.scheduleStartDaily(ruleID: id))
    }

    @Test("Disabling removes our pending requests")
    func disabledRemovesOurs() async {
        let center = MockNotificationScheduler()
        let scheduler = NotificationScheduler(center: center, defaults: freshDefaults())
        let snap = scheduleSnapshot(start: 9 * 60, days: Weekday.everyDay)

        await scheduler.sync(snapshots: [snap], enabled: true)
        #expect(center.pending.count == 1)

        await scheduler.sync(snapshots: [snap], enabled: false)
        #expect(center.pending.isEmpty)
        #expect(center.removeCallCount == 1)
    }

    @Test("An unchanged sync is a no-op (fingerprint short-circuit)")
    func fingerprintNoOps() async {
        let center = MockNotificationScheduler()
        let scheduler = NotificationScheduler(center: center, defaults: freshDefaults())
        let snap = scheduleSnapshot(start: 9 * 60, days: Weekday.everyDay)

        await scheduler.sync(snapshots: [snap], enabled: true)
        await scheduler.sync(snapshots: [snap], enabled: true)

        // The second identical sync neither added nor removed.
        #expect(center.addCallCount == 1)
        #expect(center.removeCallCount == 0)
    }

    @Test("Changing a rule's start time re-syncs and replaces the request")
    func ruleChangeReSyncs() async {
        let center = MockNotificationScheduler()
        let scheduler = NotificationScheduler(center: center, defaults: freshDefaults())
        let id = UUID()

        await scheduler.sync(
            snapshots: [scheduleSnapshot(id: id, start: 9 * 60, days: Weekday.everyDay)],
            enabled: true)
        #expect(center.pending.first?.dateComponents.hour == 8)  // 08:55

        await scheduler.sync(
            snapshots: [scheduleSnapshot(id: id, start: 10 * 60, days: Weekday.everyDay)],
            enabled: true)
        #expect(center.pending.count == 1)  // same identifier, replaced
        #expect(center.pending.first?.dateComponents.hour == 9)  // 09:55
        #expect(center.pending.first?.dateComponents.minute == 55)
    }

    @Test("The desired set is capped deterministically")
    func capsTruncation() async {
        let center = MockNotificationScheduler()
        let scheduler = NotificationScheduler(center: center, defaults: freshDefaults())
        // 70 single-day rules → 70 requests, capped to the max.
        let snapshots = (0..<70).map { i in
            scheduleSnapshot(name: "Rule \(i)", start: (8 * 60) + i, days: [.monday])
        }

        await scheduler.sync(snapshots: snapshots, enabled: true)

        #expect(center.pending.count == NotificationScheduler.maxPendingScheduleStart)
    }
}
