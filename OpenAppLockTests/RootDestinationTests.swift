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
        for hasReceived in [true, false] {
            let destination = RootDestination.resolve(
                hasCompletedOnboarding: false,
                authorizationStatus: status,
                hasReceivedAuthorizationStatus: hasReceived
            )
            #expect(destination == .onboarding)
        }
    }

    @Test(
        """
        Onboarding complete but no status received yet routes to main, so the \
        common approved launch never flashes the access-required screen while the \
        stream posts its first value
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
            .approved,
        ]
    )
    func onboardingCompleteNoStatusReceived(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasReceivedAuthorizationStatus: false
        )
        #expect(destination == .main)
    }

    @Test("Onboarding complete with a received approved status routes to main")
    func onboardingCompleteApproved() {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: .approved,
            hasReceivedAuthorizationStatus: true
        )
        #expect(destination == .main)
    }

    @Test(
        """
        Onboarding complete with a received non-approved status routes to the \
        access-required screen — including .notDetermined, which is the decisive \
        value the system reports when Screen Time is turned off in Settings
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteNonApproved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasReceivedAuthorizationStatus: true
        )
        #expect(destination == .screenTimeAccessRequired)
    }
}
