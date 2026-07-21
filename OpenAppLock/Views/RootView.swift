//
//  RootView.swift
//  OpenAppLock
//

import SwiftUI

/// Gates the app on onboarding and on Screen Time authorization. On a cold
/// launch it holds a launch screen for a brief settle window (see
/// `launchSettleDelay`) so the observed authorization stream can settle past any
/// transient `.notDetermined` before the root commits; thereafter `MainView` is
/// shown while access is approved and replaced by `ScreenTimeAccessRequiredView`
/// when it is not. See `RootDestination.resolve` for the exact rule.
struct RootView: View {
    /// How long the launch screen is held on a cold launch while the Screen Time
    /// authorization stream settles. Tunable; the UI-test harness passes `.zero`.
    static let defaultLaunchSettleDelay: Duration = .milliseconds(250)

    var launchSettleDelay: Duration = RootView.defaultLaunchSettleDelay

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(ScreenTimeAuthorization.self) private var authorization
    @Environment(NotificationAuthorization.self) private var notificationAuthorization
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasCompletedLaunchSettle = false

    var body: some View {
        Group {
            switch RootDestination.resolve(
                hasCompletedOnboarding: hasCompletedOnboarding,
                authorizationStatus: authorization.status,
                hasCompletedLaunchSettle: hasCompletedLaunchSettle
            ) {
            case .onboarding:
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            case .launchSettling:
                LaunchScreenView()
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
        // Hold the launch screen for a fixed window so the authorization stream
        // can settle past any transient `.notDetermined` it emits on a cold
        // launch, then commit to whatever it resolved to (see `RootDestination`).
        .task {
            try? await Task.sleep(for: launchSettleDelay)
            withAnimation {
                hasCompletedLaunchSettle = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await notificationAuthorization.refresh() }
        }
    }
}
