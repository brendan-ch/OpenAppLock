//
//  NotificationAuthorizationTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

private func freshDefaults() -> UserDefaults {
    let name = "notification-auth-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("Notification authorization")
struct NotificationAuthorizationTests {
    @Test("refresh adopts the provider's status and mirrors it into the app group")
    func refreshMapsStatus() async {
        let defaults = freshDefaults()
        let auth = NotificationAuthorization(
            provider: MockNotificationAuthorizationProvider(status: .authorized),
            defaults: defaults)

        await auth.refresh()

        #expect(auth.status == .authorized)
        #expect(defaults.bool(forKey: AppGroup.notificationsAuthorizedKey) == true)
    }

    @Test("A successful request becomes authorized and sets the mirror")
    func requestGranted() async {
        let defaults = freshDefaults()
        let auth = NotificationAuthorization(
            provider: MockNotificationAuthorizationProvider(
                status: .notDetermined, grantedStatus: .authorized),
            defaults: defaults)

        await auth.request()

        #expect(auth.status == .authorized)
        #expect(defaults.bool(forKey: AppGroup.notificationsAuthorizedKey) == true)
    }

    @Test("A denied request stays denied and clears the mirror")
    func requestDenied() async {
        let defaults = freshDefaults()
        // Pre-seed authorized so we can prove the denied request clears it.
        defaults.set(true, forKey: AppGroup.notificationsAuthorizedKey)
        let auth = NotificationAuthorization(
            provider: MockNotificationAuthorizationProvider(
                status: .notDetermined, grantedStatus: .denied),
            defaults: defaults)

        await auth.request()

        #expect(auth.status == .denied)
        #expect(defaults.bool(forKey: AppGroup.notificationsAuthorizedKey) == false)
    }
}
