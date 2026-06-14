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

    /// Shared defaults; falls back to standard defaults when the group
    /// container is unavailable (e.g. entitlement not provisioned yet).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
