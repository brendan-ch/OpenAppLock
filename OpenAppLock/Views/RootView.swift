//
//  RootView.swift
//  OpenAppLock
//

import SwiftUI

/// Gates the app on onboarding: until the user has walked through the welcome
/// and Screen Time permission steps, nothing else is reachable.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(ScreenTimeAuthorization.self) private var authorization
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up permission changes made in Settings while we were backgrounded.
            if phase == .active {
                authorization.refresh()
            }
        }
    }
}
