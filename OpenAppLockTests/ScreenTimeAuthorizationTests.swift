//
//  ScreenTimeAuthorizationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@MainActor
@Suite("Screen Time authorization observation")
struct ScreenTimeAuthorizationTests {
    @Test("Before the stream posts, no status has been received")
    func noStatusReceivedBeforeStreamPosts() {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .approved))
        #expect(!auth.hasReceivedStatus)
    }

    @Test("Observing the stream delivers approved and marks the status received")
    func observationDeliversApproved() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.notDetermined, .approved]
        )
        let auth = ScreenTimeAuthorization(provider: provider)

        await auth.observeStatusUpdates()

        #expect(auth.status == .approved)
        #expect(auth.hasReceivedStatus)
    }

    @Test(
        """
        A .notDetermined value from the stream is decisive: it is marked received \
        (so the root routes to access-required), not treated as still pending
        """
    )
    func observationDeliversNotDeterminedAsDecisive() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.notDetermined]
        )
        let auth = ScreenTimeAuthorization(provider: provider)

        await auth.observeStatusUpdates()

        #expect(auth.status == .notDetermined)
        #expect(auth.hasReceivedStatus)
    }
}
