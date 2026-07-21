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
        for hasCompletedLaunchSettle in [true, false] {
            let destination = RootDestination.resolve(
                hasCompletedOnboarding: false,
                authorizationStatus: status,
                hasCompletedLaunchSettle: hasCompletedLaunchSettle
            )
            #expect(destination == .onboarding)
        }
    }

    @Test(
        """
        Onboarding complete but the launch settle window has not elapsed holds the \
        launch screen, so a transient launch-time .notDetermined can't flash the \
        wrong screen before the stream settles
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
            .approved,
        ]
    )
    func onboardingCompleteStillSettling(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasCompletedLaunchSettle: false
        )
        #expect(destination == .launchSettling)
    }

    @Test("Onboarding complete and settled with approved authorization routes to main")
    func onboardingCompleteSettledApproved() {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: .approved,
            hasCompletedLaunchSettle: true
        )
        #expect(destination == .main)
    }

    @Test(
        """
        Onboarding complete and settled with a non-approved status routes to the \
        access-required screen — including .notDetermined, the decisive value the \
        system reports when Screen Time is turned off in Settings
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteSettledNonApproved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasCompletedLaunchSettle: true
        )
        #expect(destination == .screenTimeAccessRequired)
    }
}
