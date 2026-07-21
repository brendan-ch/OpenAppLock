//
//  LaunchResolvingView.swift
//  OpenAppLock
//

import SwiftUI

/// Neutral placeholder shown by `RootView` for the brief moment after a cold
/// launch while Screen Time authorization is still settling. FamilyControls
/// reports a stale `.notDetermined` before it finishes loading, so showing this
/// — rather than `ScreenTimeAccessRequiredView` — keeps the app from flashing
/// the access-required screen away the instant the real `.approved` arrives.
/// It leads with the app's own logo so it reads as a continuation of the launch
/// screen rather than an empty flash. See `RootDestination.resolve`.
struct LaunchResolvingView: View {
    var body: some View {
        VStack {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("launchResolvingView")
    }
}
