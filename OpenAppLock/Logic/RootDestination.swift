//
//  RootDestination.swift
//  OpenAppLock
//

import Foundation

/// Derives which top-level screen `RootView` should show from onboarding
/// completion, whether the launch settle window has elapsed, and observed
/// Screen Time authorization.
///
/// Screen Time authorization is observed from a stream, and on a cold launch
/// that stream can emit a transient `.notDetermined` before the real value
/// (even for an approved user) — with no reliable way to tell a transient
/// `.notDetermined` from the decisive "access is off" one. So once onboarding is
/// complete the root holds a launch screen (`.launchSettling`) until
/// `hasCompletedLaunchSettle` — a fixed delay giving the stream time to settle —
/// and only then commits: `.approved` shows `.main`, every other status shows
/// `.screenTimeAccessRequired`.
enum RootDestination: Equatable {
    case onboarding
    case launchSettling
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus,
        hasCompletedLaunchSettle: Bool
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        guard hasCompletedLaunchSettle else { return .launchSettling }
        return authorizationStatus == .approved ? .main : .screenTimeAccessRequired
    }
}
