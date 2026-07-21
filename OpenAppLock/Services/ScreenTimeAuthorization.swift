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
    /// The stream of authorization status values — the source of truth.
    /// FamilyControls publishes the current value on subscription and again on
    /// every change. Note `.notDetermined` is a *decisive* "access is off"
    /// value (it is what the system reports once Screen Time is toggled off in
    /// Settings), not a transient loading state — the synchronous
    /// `AuthorizationCenter.authorizationStatus` getter, by contrast, can stay
    /// pinned at `.notDetermined` and must not be used.
    var statusUpdates: AsyncStream<ScreenTimeAuthorizationStatus> { get }
    func requestAuthorization() async throws
}

/// Real Screen Time authorization via FamilyControls.
struct FamilyControlsAuthorizationProvider: AuthorizationProviding {
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

    /// Emits `scriptedUpdates` when provided (to model an async-settling status),
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
    private(set) var status: ScreenTimeAuthorizationStatus = .notDetermined

    /// Whether the provider's stream has delivered a value yet. The stream is
    /// the source of truth; until it posts, the root shows the main flow so the
    /// common (approved) launch never flickers — see `RootDestination`.
    private(set) var hasReceivedStatus = false
    private(set) var lastRequestFailed = false

    private let provider: AuthorizationProviding
    private var observationTask: Task<Void, Never>?

    init(provider: AuthorizationProviding) {
        self.provider = provider
    }

    /// Starts observing authorization for the app's lifetime. FamilyControls
    /// publishes the current value on subscription and on every later change
    /// (e.g. Screen Time being turned off in Settings, reported as
    /// `.notDetermined`). Safe to call more than once.
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
            hasReceivedStatus = true
        }
    }

    func request() async {
        do {
            try await provider.requestAuthorization()
            status = .approved
            lastRequestFailed = false
        } catch {
            status = .denied
            lastRequestFailed = true
        }
        hasReceivedStatus = true
    }
}
