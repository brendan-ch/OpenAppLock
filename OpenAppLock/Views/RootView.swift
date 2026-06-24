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
    @Environment(NotificationAuthorization.self) private var notificationAuthorization
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
        // Keep authorization state current app-wide: refresh at launch and on
        // every foreground, so permission changes made in the system Settings app
        // — including a notification revocation — are reflected everywhere, not
        // only when the user opens a screen that happens to read them. Notification
        // status is also mirrored into the app group here, so the scheduler keeps
        // the time-limit warn activity registered without a Settings visit.
        .task { await notificationAuthorization.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            authorization.refresh()
            Task { await notificationAuthorization.refresh() }
        }
    }
}
