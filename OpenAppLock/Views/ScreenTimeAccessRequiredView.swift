//
//  ScreenTimeAccessRequiredView.swift
//  OpenAppLock
//

import SwiftUI

/// Full-screen block shown by `RootView` whenever Screen Time access was
/// granted during onboarding but is not currently approved (revoked or reset
/// from system Settings). The app can't enforce any rule without it, so this
/// replaces `MainView` entirely rather than layering on top of it — see
/// `RootDestination.resolve`. Returning to `MainView` happens automatically:
/// `RootView` re-checks authorization on every foreground.
struct ScreenTimeAccessRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(.screenTimeAccessTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("screenTimeAccessRequiredTitle")
            Text(.screenTimeAccessDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.screenTimeAccessOpenSettingsButton)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("screenTimeAccessOpenSettingsButton")
        }
        .padding()
    }
}
