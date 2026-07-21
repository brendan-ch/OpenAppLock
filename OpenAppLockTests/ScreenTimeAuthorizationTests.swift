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
    @Test("A definitive status is available immediately at init")
    func definitiveStatusAtInit() {
        let approved = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .approved))
        #expect(approved.status == .approved)

        let denied = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .denied))
        #expect(denied.status == .denied)
    }

    @Test(
        """
        resolveAtLaunch settles past the stale launch-time .notDetermined to a \
        revoked user's real .denied, so the access-required screen can surface \
        without waiting for the next foreground
        """
    )
    func resolveAtLaunchSettlesToDenied() async {
        let provider = DelayedSettleAuthorizationProvider(settledStatus: .denied, settlesAfterReads: 2)
        let auth = ScreenTimeAuthorization(provider: provider)
        #expect(auth.status == .notDetermined)

        await auth.resolveAtLaunch()

        #expect(auth.status == .denied)
    }

    @Test("resolveAtLaunch gives up gracefully when the status never settles")
    func resolveAtLaunchGivesUpWhenNeverSettles() async {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .notDetermined))

        await auth.resolveAtLaunch()

        #expect(auth.status == .notDetermined)
    }
}
