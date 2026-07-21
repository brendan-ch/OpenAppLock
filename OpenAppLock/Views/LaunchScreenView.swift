//
//  LaunchScreenView.swift
//  OpenAppLock
//

import SwiftUI

/// A SwiftUI replica of the app's launch screen, shown briefly at cold launch
/// while Screen Time authorization settles (see `RootView` / `RootDestination`).
///
/// iOS does not allow the *actual* launch screen to be held past the first
/// rendered frame, so the standard way to "extend" it is to display a view that
/// looks identical to it. Keep this view visually in sync with the launch screen
/// (`UILaunchScreen` in Info.plist / a launch storyboard) so the hand-off from
/// the system launch screen to this replica is seamless. The launch screen is
/// currently blank, so this is just the default background; when a real launch
/// screen is added, mirror its background and logo here.
struct LaunchScreenView: View {
    var body: some View {
        Color(.systemBackground)
            .ignoresSafeArea()
            .accessibilityIdentifier("launchScreenView")
    }
}
