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
            hasCompletedOnboarding: false, authorizationStatus: status
        )
        #expect(destination == .onboarding)
    }

    @Test("Onboarding complete with approved authorization routes to main")
    func onboardingCompleteApproved() {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true, authorizationStatus: .approved
        )
        #expect(destination == .main)
    }

    @Test(
        "Onboarding complete without approval routes to the access-required screen",
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteNotApproved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true, authorizationStatus: status
        )
        #expect(destination == .screenTimeAccessRequired)
    }
}
