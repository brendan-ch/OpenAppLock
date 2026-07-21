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
        for hasResolvedAuthorization in [true, false] {
            let destination = RootDestination.resolve(
                hasCompletedOnboarding: false,
                authorizationStatus: status,
                hasResolvedAuthorization: hasResolvedAuthorization
            )
            #expect(destination == .onboarding)
        }
    }

    @Test(
        "Onboarding complete with approved authorization routes to main, even before it resolves"
    )
    func onboardingCompleteApproved() {
        for hasResolvedAuthorization in [true, false] {
            let destination = RootDestination.resolve(
                hasCompletedOnboarding: true,
                authorizationStatus: .approved,
                hasResolvedAuthorization: hasResolvedAuthorization
            )
            #expect(destination == .main)
        }
    }

    @Test(
        "Onboarding complete without approval, once resolved, routes to the access-required screen",
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteNotApprovedResolved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasResolvedAuthorization: true
        )
        #expect(destination == .screenTimeAccessRequired)
    }

    @Test(
        """
        Onboarding complete without approval and not yet resolved routes to the \
        resolving screen, so the stale launch-time status can't flash the \
        access-required screen before the real value settles
        """,
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteNotApprovedUnresolved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true,
            authorizationStatus: status,
            hasResolvedAuthorization: false
        )
        #expect(destination == .resolvingAuthorization)
    }
}
