//
//  NotificationAuthorization.swift
//  OpenAppLock
//

import Foundation
import Observation
import UserNotifications

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// Abstracts `UNUserNotificationCenter` authorization so views and tests never
/// touch it directly. Async because the system APIs are async, unlike the
/// synchronous Screen Time equivalent (`AuthorizationProviding`).
protocol NotificationAuthorizationProviding {
    func currentStatus() async -> NotificationAuthorizationStatus
    /// Prompts (if undetermined) and returns the resulting status.
    func requestAuthorization() async -> NotificationAuthorizationStatus
}

/// Real local-notification authorization via UserNotifications.
struct UserNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    func currentStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        // A throw (or the user declining) leaves the status as whatever the
        // system recorded, which the follow-up read reflects.
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        return await currentStatus()
    }

    /// Provisional and ephemeral can both deliver, so they count as authorized.
    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

/// In-memory provider for unit and UI tests. `grantedStatus` is what a request
/// resolves to, so a test can seed both the grant-success and grant-denied paths.
final class MockNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    var status: NotificationAuthorizationStatus
    let grantedStatus: NotificationAuthorizationStatus

    init(
        status: NotificationAuthorizationStatus = .notDetermined,
        grantedStatus: NotificationAuthorizationStatus = .authorized
    ) {
        self.status = status
        self.grantedStatus = grantedStatus
    }

    func currentStatus() async -> NotificationAuthorizationStatus { status }

    func requestAuthorization() async -> NotificationAuthorizationStatus {
        status = grantedStatus
        return status
    }
}

/// Observable notification-authorization state for the UI. Also mirrors "can
/// deliver right now" into the shared app group (`notificationsAuthorizedKey`)
/// so the scheduler and monitor extension gate on real authorization — see
/// ``NotificationPreferences``.
@Observable
final class NotificationAuthorization {
    private(set) var status: NotificationAuthorizationStatus
    @ObservationIgnored private let provider: NotificationAuthorizationProviding
    @ObservationIgnored private let defaults: UserDefaults

    init(
        provider: NotificationAuthorizationProviding,
        defaults: UserDefaults = AppGroup.defaults,
        initialStatus: NotificationAuthorizationStatus = .notDetermined
    ) {
        self.provider = provider
        self.defaults = defaults
        self.status = initialStatus
        persist(initialStatus)
    }

    func refresh() async {
        apply(await provider.currentStatus())
    }

    func request() async {
        apply(await provider.requestAuthorization())
    }

    private func apply(_ newStatus: NotificationAuthorizationStatus) {
        status = newStatus
        persist(newStatus)
    }

    private func persist(_ status: NotificationAuthorizationStatus) {
        defaults.set(status == .authorized, forKey: AppGroup.notificationsAuthorizedKey)
    }
}
