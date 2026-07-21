//
//  ScreenTimeAuthorizationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@MainActor
@Suite("Screen Time authorization observation")
struct ScreenTimeAuthorizationTests {
    @Test("Status starts .notDetermined until the observed stream posts a value")
    func statusStartsNotDetermined() {
        let auth = ScreenTimeAuthorization(provider: MockAuthorizationProvider(status: .approved))
        #expect(auth.status == .notDetermined)
    }

    @Test(
        """
        Draining the stream lands on its final value, so a transient launch-time \
        .notDetermined followed by the real .approved resolves to .approved
        """
    )
    func observationResolvesTransientNotDeterminedToApproved() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.notDetermined, .approved]
        )
        let auth = ScreenTimeAuthorization(provider: provider)

        await auth.observeStatusUpdates()

        #expect(auth.status == .approved)
    }

    @Test("Draining a stream whose final value is .notDetermined leaves status .notDetermined")
    func observationResolvesToNotDetermined() async {
        let provider = MockAuthorizationProvider(
            status: .notDetermined,
            scriptedUpdates: [.approved, .notDetermined]
        )
        let auth = ScreenTimeAuthorization(provider: provider)

        await auth.observeStatusUpdates()

        #expect(auth.status == .notDetermined)
    }
}
