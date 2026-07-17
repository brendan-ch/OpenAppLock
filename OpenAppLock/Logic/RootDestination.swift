//
//  RootDestination.swift
//  OpenAppLock
//

import Foundation

/// Derives which top-level screen `RootView` should show from onboarding
/// completion and current Screen Time authorization. Both `.notDetermined`
/// and `.denied` map to `.screenTimeAccessRequired`: once onboarding is
/// complete, either status means the app can no longer enforce anything, and
/// the only fix in both cases is the same visit to Settings.
enum RootDestination: Equatable {
    case onboarding
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        return authorizationStatus == .approved ? .main : .screenTimeAccessRequired
    }
}
