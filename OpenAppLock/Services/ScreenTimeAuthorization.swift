//
//  ScreenTimeAuthorization.swift
//  OpenAppLock
//

import FamilyControls
import Foundation
import Observation

enum ScreenTimeAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case approved
}

/// Abstracts FamilyControls authorization so views and tests never touch
/// `AuthorizationCenter` directly.
protocol AuthorizationProviding {
    var currentStatus: ScreenTimeAuthorizationStatus { get }
    func requestAuthorization() async throws
}

/// Real Screen Time authorization via FamilyControls.
struct FamilyControlsAuthorizationProvider: AuthorizationProviding {
    var currentStatus: ScreenTimeAuthorizationStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess: .approved
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}

/// In-memory provider for unit and UI tests.
final class MockAuthorizationProvider: AuthorizationProviding {
    var status: ScreenTimeAuthorizationStatus
    var requestShouldFail: Bool

    init(status: ScreenTimeAuthorizationStatus = .notDetermined, requestShouldFail: Bool = false) {
        self.status = status
        self.requestShouldFail = requestShouldFail
    }

    var currentStatus: ScreenTimeAuthorizationStatus { status }

    func requestAuthorization() async throws {
        if requestShouldFail {
            status = .denied
            throw FamilyControlsError.authorizationCanceled
        }
        status = .approved
    }
}

/// Observable authorization state for the UI.
@Observable
final class ScreenTimeAuthorization {
    private(set) var status: ScreenTimeAuthorizationStatus
    private(set) var lastRequestFailed = false

    private let provider: AuthorizationProviding

    init(provider: AuthorizationProviding) {
        self.provider = provider
        self.status = provider.currentStatus
    }

    func refresh() {
        status = provider.currentStatus
    }

    /// Re-reads while the launch-time status stays `.notDetermined`, giving
    /// FamilyControls a brief moment to settle so a revoked user's `.denied`
    /// surfaces promptly, then gives up so the poll can't run forever.
    func resolveAtLaunch() async {
        refresh()
        var remainingAttempts = 10
        while status == .notDetermined && remainingAttempts > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            refresh()
            remainingAttempts -= 1
        }
    }

    func request() async {
        do {
            try await provider.requestAuthorization()
            lastRequestFailed = false
        } catch {
            lastRequestFailed = true
        }
        refresh()
    }
}
