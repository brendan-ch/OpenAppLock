//
//  ScreenTimeAuthorization.swift
//  OpenAppLock
//

import Combine
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
    /// A stream of authorization status values, delivered as FamilyControls
    /// loads the real value and as it later changes. FamilyControls loads
    /// authorization asynchronously and the synchronous `currentStatus` can
    /// stay pinned at `.notDetermined` indefinitely, so this stream — not
    /// `currentStatus` — is the reliable source of the settled status.
    var statusUpdates: AsyncStream<ScreenTimeAuthorizationStatus> { get }
    func requestAuthorization() async throws
}

/// Real Screen Time authorization via FamilyControls.
struct FamilyControlsAuthorizationProvider: AuthorizationProviding {
    var currentStatus: ScreenTimeAuthorizationStatus {
        Self.mapped(AuthorizationCenter.shared.authorizationStatus)
    }

    var statusUpdates: AsyncStream<ScreenTimeAuthorizationStatus> {
        AsyncStream { continuation in
            let task = Task {
                for await status in AuthorizationCenter.shared.$authorizationStatus.values {
                    continuation.yield(Self.mapped(status))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    private static func mapped(_ status: AuthorizationStatus) -> ScreenTimeAuthorizationStatus {
        switch status {
        case .approved, .approvedWithDataAccess: .approved
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

/// In-memory provider for unit and UI tests.
final class MockAuthorizationProvider: AuthorizationProviding {
    var status: ScreenTimeAuthorizationStatus
    var requestShouldFail: Bool
    private let scriptedUpdates: [ScreenTimeAuthorizationStatus]?

    init(
        status: ScreenTimeAuthorizationStatus = .notDetermined,
        requestShouldFail: Bool = false,
        scriptedUpdates: [ScreenTimeAuthorizationStatus]? = nil
    ) {
        self.status = status
        self.requestShouldFail = requestShouldFail
        self.scriptedUpdates = scriptedUpdates
    }

    var currentStatus: ScreenTimeAuthorizationStatus { status }

    /// Emits `scriptedUpdates` when provided (to mimic an async-settling status),
    /// otherwise the current status once, then finishes.
    var statusUpdates: AsyncStream<ScreenTimeAuthorizationStatus> {
        let values = scriptedUpdates ?? [status]
        return AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }

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
    private var observationTask: Task<Void, Never>?

    init(provider: AuthorizationProviding) {
        self.provider = provider
        self.status = provider.currentStatus
    }

    /// Starts observing authorization changes for the app's lifetime. The
    /// synchronous `currentStatus` can stay pinned at `.notDetermined` because
    /// FamilyControls loads it asynchronously, so draining the provider's
    /// stream is what delivers the settled value and any later change (e.g. a
    /// revocation from Settings). Safe to call more than once.
    func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            await self?.observeStatusUpdates()
        }
    }

    /// Drains the provider's status stream into `status`. Split out from
    /// `startObserving()` so tests can await it deterministically.
    func observeStatusUpdates() async {
        for await value in provider.statusUpdates {
            status = value
        }
    }

    func refresh() {
        status = provider.currentStatus
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
