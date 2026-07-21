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
///
/// The `.approved` check comes first and needs no resolution, but a
/// *non*-approved status at launch is not trusted until it has resolved. The
/// FamilyControls framework loads authorization asynchronously and reports a
/// stale `.notDetermined` for the first moments after a cold launch — even for
/// a user who granted access — so committing to `.screenTimeAccessRequired`
/// immediately would flash that screen away the instant the real `.approved`
/// arrives. Until `hasResolvedAuthorization` is true, a not-yet-approved status
/// routes to `.resolvingAuthorization` (a neutral placeholder) instead.
enum RootDestination: Equatable {
    case onboarding
    case resolvingAuthorization
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus,
        hasResolvedAuthorization: Bool
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        if authorizationStatus == .approved { return .main }
        return hasResolvedAuthorization ? .screenTimeAccessRequired : .resolvingAuthorization
    }
}
