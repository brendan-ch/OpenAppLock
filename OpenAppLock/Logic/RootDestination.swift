//
//  RootDestination.swift
//  OpenAppLock
//

import Foundation

/// Derives which top-level screen `RootView` should show from onboarding
/// completion and current Screen Time authorization. Only `.denied` gates the
/// app; `.notDetermined` routes to `.main` so the common launch (access already
/// granted, but reported as a stale `.notDetermined` while FamilyControls loads)
/// never flashes the access-required screen. A genuinely revoked user may see
/// `.main` briefly before the status settles to `.denied`.
enum RootDestination: Equatable {
    case onboarding
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        return authorizationStatus == .denied ? .screenTimeAccessRequired : .main
    }
}
