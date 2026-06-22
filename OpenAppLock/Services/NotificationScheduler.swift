//
//  NotificationScheduler.swift
//  OpenAppLock
//

import Foundation
import UserNotifications
import os

/// Abstracts `UNUserNotificationCenter`'s pending-request management so the
/// reconciliation can be unit-tested without scheduling real notifications.
protocol LocalNotificationScheduling: Sendable {
    /// The identifiers of currently-pending `schedule-start-*` requests.
    func pendingScheduleStartIdentifiers() async -> [String]
    /// Removes the given identifiers, then (re)adds the planned requests —
    /// `add` with an existing identifier replaces it, so changed content updates.
    func replaceScheduleStart(remove: [String], add: [PlannedNotification]) async
}

/// Real scheduling via UserNotifications: weekly (or daily, when collapsed)
/// repeating calendar triggers.
struct UserNotificationScheduler: LocalNotificationScheduling {
    func pendingScheduleStartIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map(\.identifier)
            .filter(NotificationIDs.isScheduleStart)
    }

    func replaceScheduleStart(remove: [String], add: [PlannedNotification]) async {
        let center = UNUserNotificationCenter.current()
        if !remove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: remove)
        }
        for planned in add {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: planned.dateComponents, repeats: true)
            // Explicit completion handler selects the fire-and-forget overload
            // (the bare `add(_:)` resolves to `async throws` in this async context).
            center.add(
                UNNotificationRequest(
                    identifier: planned.identifier, content: content, trigger: trigger),
                withCompletionHandler: nil)
        }
    }
}

/// Keeps the system's pending "a schedule rule starts in 5 minutes"
/// notifications in step with the current rules. An `actor` so the
/// fire-and-forget calls from `RuleEnforcer.refresh` (which also runs on a 30 s
/// loop) serialize instead of racing; a fingerprint short-circuits the common
/// no-op so the loop doesn't churn.
actor NotificationScheduler {
    /// iOS silently caps an app at 64 pending requests; stay well under so other
    /// requests (and headroom) survive. Per-day requests are collapsed to a
    /// single daily one for every-day rules before this cap is reached.
    static let maxPendingScheduleStart = 60
    private static let fingerprintKey = "notificationScheduleFingerprint"
    private static let log = Logger(
        subsystem: "dev.bchen.OpenAppLock", category: "NotificationScheduler")

    private let center: LocalNotificationScheduling
    private let defaults: UserDefaults

    init(
        center: LocalNotificationScheduling = UserNotificationScheduler(),
        defaults: UserDefaults = AppGroup.defaults
    ) {
        self.center = center
        self.defaults = defaults
    }

    func sync(snapshots: [RuleSnapshot], enabled: Bool) async {
        let fingerprint = Self.fingerprint(enabled: enabled, snapshots: snapshots)
        guard fingerprint != defaults.string(forKey: Self.fingerprintKey) else { return }

        let desired =
            enabled ? capped(ScheduleStartNotificationPlan.requests(for: snapshots)) : []
        let desiredIDs = Set(desired.map(\.identifier))
        let pendingIDs = await center.pendingScheduleStartIdentifiers()
        let remove = pendingIDs.filter { !desiredIDs.contains($0) }

        // (Re)add all desired — add replaces a same-identifier request whose time
        // or text changed; remove drops the ones no longer wanted.
        await center.replaceScheduleStart(remove: remove, add: desired)
        defaults.set(fingerprint, forKey: Self.fingerprintKey)
    }

    /// Deterministically keeps the soonest-in-the-day requests when the desired
    /// set would exceed the cap, logging what was dropped (never expected for a
    /// realistic rule count).
    private func capped(_ requests: [PlannedNotification]) -> [PlannedNotification] {
        guard requests.count > Self.maxPendingScheduleStart else { return requests }
        let sorted = requests.sorted { Self.sortKey($0) < Self.sortKey($1) }
        let kept = Array(sorted.prefix(Self.maxPendingScheduleStart))
        Self.log.warning(
            "Schedule-start notifications exceed the cap; dropping \(requests.count - kept.count)")
        return kept
    }

    private static func sortKey(_ request: PlannedNotification) -> String {
        let minutes = (request.dateComponents.hour ?? 0) * 60 + (request.dateComponents.minute ?? 0)
        return String(format: "%04d|%@", minutes, request.identifier)
    }

    /// Captures everything that changes the desired set: the master enable flag,
    /// the lead time, and each schedule rule's identity/window/days/has-apps.
    /// Pause is deliberately excluded — a soft unblock only affects an already
    /// active window whose start has passed, so it never collides with a
    /// "starting soon" notification.
    private static func fingerprint(enabled: Bool, snapshots: [RuleSnapshot]) -> String {
        let rules =
            snapshots
            .filter { $0.kind == .schedule }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                "\($0.id.uuidString)|\($0.isEnabled)|\($0.name)|\($0.startMinutes)|"
                    + "\($0.endMinutes)|\($0.dayNumbers.sorted())|\($0.selectionData != nil)"
            }
        return "\(enabled)|\(ScheduleStartNotificationPlan.leadMinutes)|"
            + rules.joined(separator: ",")
    }
}

/// Records scheduling calls for tests, emulating "add replaces a same-identifier
/// request".
final class MockNotificationScheduler: LocalNotificationScheduling, @unchecked Sendable {
    private(set) var pending: [PlannedNotification] = []
    private(set) var removeCallCount = 0
    private(set) var addCallCount = 0

    func pendingScheduleStartIdentifiers() async -> [String] { pending.map(\.identifier) }

    func replaceScheduleStart(remove: [String], add: [PlannedNotification]) async {
        let dropped = Set(remove).union(add.map(\.identifier))
        pending.removeAll { dropped.contains($0.identifier) }
        pending.append(contentsOf: add)
        if !remove.isEmpty { removeCallCount += 1 }
        if !add.isEmpty { addCallCount += 1 }
    }
}
