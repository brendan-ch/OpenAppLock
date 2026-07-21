//
//  ScreenTimeAuthorizationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

/// Provider that reports `.notDetermined` for its first reads and then the
/// settled status, mimicking how FamilyControls loads authorization
/// asynchronously and reports a stale `.notDetermined` right after a cold
/// launch before the real value arrives.
@MainActor
private final class DelayedSettleAuthorizationProvider: AuthorizationProviding {
    private var reads = 0
    private let settledStatus: ScreenTimeAuthorizationStatus
    private let settlesAfterReads: Int

    init(settledStatus: ScreenTimeAuthorizationStatus, settlesAfterReads: Int) {
        self.settledStatus = settledStatus
        self.settlesAfterReads = settlesAfterReads
    }

    var currentStatus: ScreenTimeAuthorizationStatus {
        defer { reads += 1 }
        return reads >= settlesAfterReads ? settledStatus : .notDetermined
    }

    func requestAuthorization() async throws {}
}

@MainActor
@Suite("Screen Time authorization launch resolution")
struct ScreenTimeAuthorizationTests {
    @Test("A definitive status is resolved immediately at init, without waiting")
    func definitiveStatusResolvesAtInit() {
        let approved = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .approved))
        #expect(approved.hasResolvedStatus)

        let denied = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .denied))
        #expect(denied.hasResolvedStatus)
    }

    @Test("A .notDetermined status at init is not yet resolved")
    func notDeterminedIsUnresolvedAtInit() {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .notDetermined))
        #expect(!auth.hasResolvedStatus)
    }

    @Test(
        """
        resolveAtLaunch waits for the async-settling status to become approved, \
        so the stale launch-time .notDetermined never routes to access-required
        """
    )
    func resolveAtLaunchWaitsForApproved() async {
        let provider = DelayedSettleAuthorizationProvider(settledStatus: .approved, settlesAfterReads: 2)
        let auth = ScreenTimeAuthorization(provider: provider)
        #expect(auth.status == .notDetermined)
        #expect(!auth.hasResolvedStatus)

        await auth.resolveAtLaunch()

        #expect(auth.status == .approved)
        #expect(auth.hasResolvedStatus)
    }

    @Test("resolveAtLaunch gives up and marks resolved when the status never settles")
    func resolveAtLaunchGivesUpWhenNeverSettles() async {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .notDetermined))

        await auth.resolveAtLaunch()

        #expect(auth.status == .notDetermined)
        #expect(auth.hasResolvedStatus)
    }
}
