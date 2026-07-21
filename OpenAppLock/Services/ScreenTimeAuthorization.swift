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

    /// Whether the launch-time status has settled to a value the UI can trust.
    /// FamilyControls loads authorization asynchronously and reports a stale
    /// `.notDetermined` right after a cold launch, so until this is true a
    /// not-yet-approved status must not commit to the access-required screen —
    /// see `RootDestination`. An `.approved` or `.denied` read is definitive
    /// and resolves immediately; only a `.notDetermined` read stays unresolved
    /// until it either settles or `resolveAtLaunch()` gives up.
    private(set) var hasResolvedStatus: Bool

    private let provider: AuthorizationProviding

    init(provider: AuthorizationProviding) {
        self.provider = provider
        let initial = provider.currentStatus
        self.status = initial
        self.hasResolvedStatus = initial != .notDetermined
    }

    func refresh() {
        status = provider.currentStatus
        if status != .notDetermined { hasResolvedStatus = true }
    }

    /// Resolves the launch-time status, tolerating the stale `.notDetermined`
    /// FamilyControls reports before it finishes loading. Re-reads the status
    /// while it stays `.notDetermined`, giving the framework a brief moment to
    /// settle to the real value; if it never does, gives up and marks the
    /// status resolved so a genuinely unauthorized state isn't stuck on the
    /// resolving screen forever.
    func resolveAtLaunch() async {
        refresh()
        var remainingAttempts = 10
        while status == .notDetermined && remainingAttempts > 0 {
            try? await Task.sleep(for: .milliseconds(50))
            refresh()
            remainingAttempts -= 1
        }
        hasResolvedStatus = true
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
