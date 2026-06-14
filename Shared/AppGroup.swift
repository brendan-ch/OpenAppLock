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

    /// Shared defaults; falls back to standard defaults when the group
    /// container is unavailable (e.g. entitlement not provisioned yet).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
