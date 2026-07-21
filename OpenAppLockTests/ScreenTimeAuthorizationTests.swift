//
//  ScreenTimeAuthorizationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@MainActor
@Suite("Screen Time authorization observation")
struct ScreenTimeAuthorizationTests {
    @Test("Init seeds status from the provider's current status")
    func initSeedsFromCurrentStatus() {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .notDetermined))
        #expect(auth.status == .notDetermined)
    }

    @Test(
        """
        Observing the provider's stream settles status past the stale launch-time \
        .notDetermined to the real .approved, which the synchronous getter never \
        delivered
        """
    )
    func observationSettlesToApproved() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.notDetermined, .approved]
        )
        let auth = ScreenTimeAuthorization(provider: provider)
        #expect(auth.status == .notDetermined)

        await auth.observeStatusUpdates()

        #expect(auth.status == .approved)
    }

    @Test("Observing the provider's stream surfaces a revoked user's .denied")
    func observationSettlesToDenied() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.notDetermined, .denied]
        )
        let auth = ScreenTimeAuthorization(provider: provider)

        await auth.observeStatusUpdates()

        #expect(auth.status == .denied)
    }
}
