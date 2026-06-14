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
    static let uninstallProtectionKey = "uninstallProtectionEnabled"

    @ObservationIgnored private let defaults: UserDefaults

    var uninstallProtectionEnabled: Bool {
        didSet {
            defaults.set(uninstallProtectionEnabled, forKey: Self.uninstallProtectionKey)
        }
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        // Property observers don't fire during init, so this load doesn't write back.
        self.uninstallProtectionEnabled = defaults.bool(forKey: Self.uninstallProtectionKey)
    }

    /// Clears the persisted value — used by UI-test launches, since the
    /// app-group suite is not wiped between runs the way the SwiftData store is.
    static func resetForTesting(defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: uninstallProtectionKey)
    }
}

/// In-memory settings for unit tests.
final class MockAppSettings: AppSettingsReading {
    var uninstallProtectionEnabled: Bool

    init(uninstallProtectionEnabled: Bool = false) {
        self.uninstallProtectionEnabled = uninstallProtectionEnabled
    }
}
