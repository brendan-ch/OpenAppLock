//
//  RootDestinationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@MainActor
@Suite("Root destination resolution")
struct RootDestinationTests {
    @Test(
        "Onboarding incomplete always routes to onboarding, regardless of authorization",
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
            .approved,
        ]
    )
    func onboardingIncomplete(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: false,
            authorizationStatus: status
        )
        #expect(destination == .onboarding)
    }

    @Test(
        """
        Onboarding complete routes to main for every status except denied, so a \
        stale launch-time .notDetermined shows the real app instead of flashing \
        the access-required screen
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.approved,
            .notDetermined,
        ]
    )
    func onboardingCompleteNonDeniedRoutesToMain(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status
        )
        #expect(destination == .main)
    }

    @Test("Onboarding complete with denied authorization routes to the access-required screen")
    func onboardingCompleteDenied() {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: .denied
        )
        #expect(destination == .screenTimeAccessRequired)
    }
}
