//
//  NotificationPreferencesTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

private func freshDefaults() -> UserDefaults {
    let name = "notification-prefs-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("App settings — notification toggles")
struct AppSettingsNotificationTests {
    @Test("Both notification toggles default to off")
    func defaultsOff() {
        let store = AppSettingsStore(defaults: freshDefaults())
        #expect(store.notifyScheduleStartEnabled == false)
        #expect(store.notifyTimeLimitEndingEnabled == false)
    }

    @Test("Toggles persist to the shared defaults")
    func persists() {
        let defaults = freshDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.notifyScheduleStartEnabled = true
        store.notifyTimeLimitEndingEnabled = true

        #expect(defaults.bool(forKey: AppGroup.notifyScheduleStartKey) == true)
        #expect(defaults.bool(forKey: AppGroup.notifyTimeLimitEndingKey) == true)
        // A fresh store over the same defaults reads the persisted values back.
        let reloaded = AppSettingsStore(defaults: defaults)
        #expect(reloaded.notifyScheduleStartEnabled == true)
        #expect(reloaded.notifyTimeLimitEndingEnabled == true)
    }

    @Test("resetForTesting clears the notification keys")
    func resetClears() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: AppGroup.notifyScheduleStartKey)
        defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)

        AppSettingsStore.resetForTesting(defaults: defaults)

        #expect(defaults.bool(forKey: AppGroup.notifyScheduleStartKey) == false)
        #expect(defaults.bool(forKey: AppGroup.notifyTimeLimitEndingKey) == false)
        #expect(defaults.bool(forKey: AppGroup.notificationsAuthorizedKey) == false)
    }
}

@MainActor
@Suite("Notification preferences — effective gates")
struct NotificationPreferencesTests {
    @Test("A type is enabled only when authorized AND its toggle is on")
    func requiresAuthAndToggle() {
        let defaults = freshDefaults()
        let prefs = NotificationPreferences(defaults: defaults)

        // Toggle on, not authorized → effective off.
        defaults.set(true, forKey: AppGroup.notifyScheduleStartKey)
        defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        #expect(prefs.scheduleStartEnabled == false)
        #expect(prefs.timeLimitEndingEnabled == false)

        // Authorized too → effective on.
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
        #expect(prefs.scheduleStartEnabled == true)
        #expect(prefs.timeLimitEndingEnabled == true)
    }

    @Test("Revoking authorization disables both types without touching the raw toggles")
    func revokeAuthDisables() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: AppGroup.notifyScheduleStartKey)
        defaults.set(true, forKey: AppGroup.notifyTimeLimitEndingKey)
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
        let prefs = NotificationPreferences(defaults: defaults)
        #expect(prefs.scheduleStartEnabled == true)

        defaults.set(false, forKey: AppGroup.notificationsAuthorizedKey)
        #expect(prefs.scheduleStartEnabled == false)
        #expect(prefs.timeLimitEndingEnabled == false)
        // Raw toggles preserved.
        #expect(prefs.rawScheduleStartEnabled == true)
        #expect(prefs.rawTimeLimitEndingEnabled == true)
    }
}
