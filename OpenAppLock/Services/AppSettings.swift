//
//  AppSettings.swift
//  OpenAppLock
//

import Foundation
import Observation

/// Read access to the app-wide settings the enforcer consults. Injected into
/// `RuleEnforcer` so the uninstall-protection decision has a single,
/// test-mockable source of truth.
protocol AppSettingsReading: AnyObject {
    /// Whether the user has opted into denying device app removal while a Hard
    /// Mode rule is actively blocking.
    var uninstallProtectionEnabled: Bool { get }
}

/// The settings store, backed by the shared app-group defaults so the value
/// persists across launches (and is reachable by the extensions in future).
/// Observable so the Settings screen's toggle stays in sync.
@Observable
final class AppSettingsStore: AppSettingsReading {
    /// The single source of truth for the key is `AppGroup`, so the app and the
    /// extensions read and write the same defaults entry.
    static let uninstallProtectionKey = AppGroup.uninstallProtectionKey

    /// Raw opt-in toggles for the two notification types. The effective gates
    /// (these ANDed with notification authorization) live in
    /// ``NotificationPreferences``; these are just the user's stored preference,
    /// kept so they survive a permission round-trip.
    static let notifyScheduleStartKey = AppGroup.notifyScheduleStartKey
    static let notifyTimeLimitEndingKey = AppGroup.notifyTimeLimitEndingKey

    @ObservationIgnored private let defaults: UserDefaults

    var uninstallProtectionEnabled: Bool {
        didSet {
            defaults.set(uninstallProtectionEnabled, forKey: Self.uninstallProtectionKey)
        }
    }

    /// "Notify me 5 minutes before a schedule rule starts."
    var notifyScheduleStartEnabled: Bool {
        didSet {
            defaults.set(notifyScheduleStartEnabled, forKey: Self.notifyScheduleStartKey)
        }
    }

    /// "Notify me when a time-limit rule has 5 minutes of allowance left."
    var notifyTimeLimitEndingEnabled: Bool {
        didSet {
            defaults.set(notifyTimeLimitEndingEnabled, forKey: Self.notifyTimeLimitEndingKey)
        }
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        // Property observers don't fire during init, so these loads don't write back.
        self.uninstallProtectionEnabled = defaults.bool(forKey: Self.uninstallProtectionKey)
        self.notifyScheduleStartEnabled = defaults.bool(forKey: Self.notifyScheduleStartKey)
        self.notifyTimeLimitEndingEnabled = defaults.bool(forKey: Self.notifyTimeLimitEndingKey)
    }

    /// Clears the persisted values — used by UI-test launches, since the
    /// app-group suite is not wiped between runs the way the SwiftData store is.
    static func resetForTesting(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: uninstallProtectionKey)
        defaults.removeObject(forKey: notifyScheduleStartKey)
        defaults.removeObject(forKey: notifyTimeLimitEndingKey)
        defaults.removeObject(forKey: AppGroup.notificationsAuthorizedKey)
    }
}

/// In-memory settings for unit tests.
final class MockAppSettings: AppSettingsReading {
    var uninstallProtectionEnabled: Bool

    init(uninstallProtectionEnabled: Bool = false) {
        self.uninstallProtectionEnabled = uninstallProtectionEnabled
    }
}
