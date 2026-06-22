//
//  AppGroup.swift
//  OpenAppLock
//

import Foundation

/// The app group shared by the app and its Screen Time extensions. Usage
/// tracking and rule snapshots live in its UserDefaults suite so the
/// DeviceActivity monitor and shield extensions can read and write them.
enum AppGroup {
    static let identifier = "group.dev.bchen.OpenAppLock"

    /// Defaults key for the Uninstall Protection opt-in. Lives here (not on the
    /// app-only `AppSettingsStore`) so the Screen Time extensions can read the
    /// same setting when recomputing app-removal denial in the background.
    static let uninstallProtectionKey = "uninstallProtectionEnabled"

    /// Raw opt-in for the "a schedule rule starts in 5 minutes" notification.
    static let notifyScheduleStartKey = "notifyScheduleStartEnabled"

    /// Raw opt-in for the "a time-limit rule has 5 minutes of allowance left"
    /// notification. Read by the monitor extension when a warn event fires, so it
    /// lives in the shared suite (not the app-only `AppSettingsStore`).
    static let notifyTimeLimitEndingKey = "notifyTimeLimitEndingEnabled"

    /// Mirror of "notifications are actually grantable/deliverable right now",
    /// written by `NotificationAuthorization`. Every effective notification gate
    /// ANDs this with its type toggle, so revoking system permission disables
    /// both notification types (and tears down their scheduling) on the next
    /// foreground auth refresh — see ``NotificationPreferences``.
    static let notificationsAuthorizedKey = "notificationsAuthorized"

    /// Shared defaults; falls back to standard defaults when the group
    /// container is unavailable (e.g. entitlement not provisioned yet).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
