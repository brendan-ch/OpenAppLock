//
//  OnboardingView.swift
//  OpenAppLock
//

import SwiftUI

/// Two-step onboarding using system styling: a welcome screen, then the
/// Screen Time permission request. Onboarding only completes once
/// authorization is approved — the app cannot block anything without it.
struct OnboardingView: View {
    @Environment(ScreenTimeAuthorization.self) private var authorization
    @Environment(\.openURL) private var openURL
    let onComplete: () -> Void

    private enum Step {
        case welcome
        case permission
    }

    @State private var step = Step.welcome
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            switch step {
            case .welcome: welcome
            case .permission: permission
            }
            Spacer()
            footer
        }
        .padding()
    }

    /// Shared vertical rhythm so both onboarding steps line up.
    private var stepSpacing: CGFloat { 20 }

    private var welcome: some View {
        VStack(spacing: stepSpacing) {
            appLogo
            Text(.onboardingWelcomeTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(.onboardingWelcomeDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// The real app icon, shown as a rounded tile so the welcome screen leads
    /// with the app's own identity rather than a generic symbol.
    private var appLogo: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .accessibilityHidden(true)
    }

    private var permission: some View {
        VStack(spacing: stepSpacing) {
            Image(systemName: "hourglass")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(.onboardingAllowScreenTime)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                bullet("shield.fill", CopyKey.onboardingScreenTimeFrameworkBullet.string)
                bullet("hand.raised.fill", CopyKey.onboardingActivityStaysPrivateBullet.string)
                bullet("gearshape.fill", CopyKey.onboardingChangeAnytimeBullet.string)
            }
            if authorization.status == .denied || authorization.lastRequestFailed {
                VStack(spacing: 10) {
                    Text(.onboardingAccessDeclinedMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("permissionDeniedLabel")
                    Button(CopyKey.onboardingOpenSettingsButton.resource) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .accessibilityIdentifier("openSettingsButton")
                }
            }
        }
    }

    private func bullet(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .welcome:
            pillButton(CopyKey.onboardingContinueButton.string, identifier: "onboardingContinueButton") {
                step = .permission
            }
        case .permission:
            pillButton(
                isRequesting ? CopyKey.onboardingRequesting.string : CopyKey.onboardingAllowScreenTime.string,
                identifier: "allowScreenTimeButton"
            ) {
                guard !isRequesting else { return }
                isRequesting = true
                Task {
                    await authorization.request()
                    isRequesting = false
                    if authorization.status == .approved {
                        onComplete()
                    }
                }
            }
        }
    }

    private func pillButton(
        _ title: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }
}
