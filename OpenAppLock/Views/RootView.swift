//
//  RootView.swift
//  OpenAppLock
//

import SwiftUI

/// Gates the app on onboarding and on Screen Time authorization: until the
/// user has walked through the welcome and permission steps, nothing else is
/// reachable, and if access is later revoked from system Settings,
/// `MainView` is replaced by `ScreenTimeAccessRequiredView` until access is
/// restored. See `RootDestination.resolve` for the exact rule.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(ScreenTimeAuthorization.self) private var authorization
    @Environment(NotificationAuthorization.self) private var notificationAuthorization
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch RootDestination.resolve(
                hasCompletedOnboarding: hasCompletedOnboarding,
                authorizationStatus: authorization.status,
                hasReceivedAuthorizationStatus: authorization.hasReceivedStatus
            ) {
            case .onboarding:
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            case .screenTimeAccessRequired:
                ScreenTimeAccessRequiredView()
                    .onAppear {
                        Diag.log(
                            .lifecycle,
                            "screen time authorization not approved — showing access-required overlay"
                        )
                    }
            case .main:
                MainView()
            }
        }
        // Keep authorization state current app-wide. Screen Time authorization
        // is *observed* rather than polled: FamilyControls loads it
        // asynchronously and the synchronous getter can stay pinned at
        // `.notDetermined`, so `startObserving()` drains the published stream to
        // get the settled value and any later change (see `ScreenTimeAuthorization`).
        //
        // Notification status is still refreshed on launch and every foreground
        // — and mirrored into the app group — so a change made in Settings is
        // reflected everywhere and the scheduler keeps the time-limit warn
        // activity registered without a Settings visit.
        .task {
            authorization.startObserving()
            await notificationAuthorization.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await notificationAuthorization.refresh() }
        }
    }
}
