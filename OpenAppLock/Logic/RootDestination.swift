//
//  RootDestination.swift
//  OpenAppLock
//

import Foundation

/// Derives which top-level screen `RootView` should show from onboarding
/// completion and observed Screen Time authorization.
///
/// The status comes from an observed stream, not a synchronous read. Until that
/// stream has delivered a value (`hasReceivedAuthorizationStatus` is false), the
/// root shows `.main` so the common approved launch never flickers. Once a value
/// has arrived, only `.approved` shows `.main`; every other status — including
/// `.notDetermined`, the decisive value the system reports when Screen Time is
/// turned off in Settings — routes to `.screenTimeAccessRequired`.
enum RootDestination: Equatable {
    case onboarding
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus,
        hasReceivedAuthorizationStatus: Bool
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        guard hasReceivedAuthorizationStatus else { return .main }
        return authorizationStatus == .approved ? .main : .screenTimeAccessRequired
    }
}
