//
//  ScheduleStartNotificationPlan.swift
//  OpenAppLock
//

import Foundation

/// Stable identifiers for the locally-scheduled notifications the app owns.
/// Centralised so building and recognising them can't drift apart.
enum NotificationIDs {
    static let scheduleStartPrefix = "schedule-start-"

    /// A per-weekday "schedule starting soon" request.
    static func scheduleStart(ruleID: UUID, weekday: Weekday) -> String {
        "\(scheduleStartPrefix)\(ruleID.uuidString)-\(weekday.rawValue)"
    }

    /// The collapsed every-day "schedule starting soon" request (fires daily,
    /// one request instead of seven).
    static func scheduleStartDaily(ruleID: UUID) -> String {
        "\(scheduleStartPrefix)\(ruleID.uuidString)-daily"
    }

    static func isScheduleStart(_ identifier: String) -> Bool {
        identifier.hasPrefix(scheduleStartPrefix)
    }
}

/// One planned local notification: a stable identifier, the calendar trigger
/// components (weekly when a `weekday` is present, daily when not), and content.
struct PlannedNotification: Equatable, Sendable {
    let identifier: String
    let dateComponents: DateComponents
    let title: String
    let body: String
}

/// Pure planner for the "a schedule rule starts in N minutes" notifications.
///
/// A schedule window's start is a recurring wall-clock moment, so iOS can own
/// delivery via repeating `UNCalendarNotificationTrigger`s — no background wake
/// needed, reliable while the app is closed. This computes *what* to schedule;
/// `NotificationScheduler` reconciles it against what is pending.
///
/// A rule is included only when it can actually start a fresh block the user
/// would want warning of: it is an enabled `.schedule` rule, has enabled days,
/// blocks at least one app, and is not a 24-hour (`start == end`) window — a
/// perpetual window never meaningfully "starts".
enum ScheduleStartNotificationPlan {
    static let leadMinutes = 5
    private static let minutesPerDay = 24 * 60

    static func requests(
        for snapshots: [RuleSnapshotDTO], leadMinutes: Int = leadMinutes
    ) -> [PlannedNotification] {
        snapshots.flatMap { requests(for: $0, leadMinutes: leadMinutes) }
    }

    private static func requests(
        for snapshot: RuleSnapshotDTO, leadMinutes: Int
    ) -> [PlannedNotification] {
        guard snapshot.kind == .schedule, snapshot.isEnabled,
              !snapshot.days.isEmpty, snapshot.selectionData != nil,
              snapshot.startMinutes != snapshot.endMinutes
        else { return [] }

        // All enabled days share the same start, so the fire *minute* is a single
        // value and the negative-lead rollover (the warning crossing back over
        // midnight) shifts every fire day to the previous weekday uniformly.
        let raw = snapshot.startMinutes - leadMinutes
        let rollsOver = raw < 0
        let fireMinute = rollsOver ? raw + minutesPerDay : raw
        let hour = fireMinute / 60
        let minute = fireMinute % 60

        let fireWeekdays = snapshot.days.map { rollsOver ? previousWeekday($0) : $0 }
        let title = "Heads up"
        let body = "\(snapshot.name) starts in \(leadMinutes) minutes."

        // Every day enabled → one daily trigger instead of seven weekly ones, so
        // a handful of all-week rules don't burn through iOS's 64 pending cap.
        if Set(fireWeekdays) == Weekday.everyDay {
            return [
                PlannedNotification(
                    identifier: NotificationIDs.scheduleStartDaily(ruleID: snapshot.id),
                    dateComponents: DateComponents(hour: hour, minute: minute),
                    title: title, body: body)
            ]
        }

        return fireWeekdays
            .sorted { $0.rawValue < $1.rawValue }
            .map { weekday in
                PlannedNotification(
                    identifier: NotificationIDs.scheduleStart(ruleID: snapshot.id, weekday: weekday),
                    dateComponents: DateComponents(
                        hour: hour, minute: minute, weekday: weekday.rawValue),
                    title: title, body: body)
            }
    }

    /// The calendar weekday before `weekday`, wrapping Sunday (1) back to
    /// Saturday (7). Used when the lead time pushes the warning into the prior day.
    private static func previousWeekday(_ weekday: Weekday) -> Weekday {
        Weekday(rawValue: weekday == .sunday ? 7 : weekday.rawValue - 1) ?? weekday
    }
}
