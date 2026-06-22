//
//  NotificationPreferences.swift
//  OpenAppLock
//

import Foundation

/// The *effective* notification gates, read by both the app (when deciding what
/// to schedule) and the monitor extension (when a warn event fires). Each type
/// is enabled only when the user's raw toggle is on **and** notifications are
/// actually authorized — so revoking system permission disables delivery and
/// scheduling without the user having to also flip the toggles off.
///
/// Pure and dependency-free (no `UserNotifications` import) so it is safe to
/// compile into every target via `Shared/`.
struct NotificationPreferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    /// Whether notifications can currently be delivered (the mirror written by
    /// `NotificationAuthorization`).
    var isAuthorized: Bool {
        defaults.bool(forKey: AppGroup.notificationsAuthorizedKey)
    }

    /// The user's raw "schedule starting soon" opt-in, ignoring authorization.
    var rawScheduleStartEnabled: Bool {
        defaults.bool(forKey: AppGroup.notifyScheduleStartKey)
    }

    /// The user's raw "time limit almost up" opt-in, ignoring authorization.
    var rawTimeLimitEndingEnabled: Bool {
        defaults.bool(forKey: AppGroup.notifyTimeLimitEndingKey)
    }

    /// Effective gate for the "a schedule rule starts in 5 minutes" notification.
    var scheduleStartEnabled: Bool {
        isAuthorized && rawScheduleStartEnabled
    }

    /// Effective gate for the "a time-limit rule has 5 minutes left" notification.
    var timeLimitEndingEnabled: Bool {
        isAuthorized && rawTimeLimitEndingEnabled
    }
}
