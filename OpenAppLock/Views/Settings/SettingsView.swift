//
//  SettingsView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Settings tab: device-level protection and app-list management.
struct SettingsView: View {
    @Environment(RuleEnforcer.self) private var enforcer
    @Environment(AppSettingsStore.self) private var settings
    @Query private var rules: [BlockingRule]

    /// Local mirror of the persisted setting; the explicit binding below writes
    /// it through to the store and re-enforces in one step.
    @State private var uninstallProtectionOn = false

    /// UI-test only: the destination of the most recent link tap, captured by
    /// the `openURL` interceptor so a test can assert it (see `linkSection`).
    @State private var lastOpenedLink: URL?

    private let launch = LaunchConfiguration.current

    /// The GitHub destination: a UI-test override when present, otherwise the
    /// configured build-setting value read centrally through `AppLinks`.
    private var gitHubURL: URL? {
        AppLinks.url(from: launch.gitHubURLOverride) ?? AppLinks.gitHub
    }

    /// The website destination, resolved like ``gitHubURL``.
    private var websiteURL: URL? {
        AppLinks.url(from: launch.websiteURLOverride) ?? AppLinks.website
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isUninstallProtectionLocked {
                        // Mirror the Home "Currently Blocking" hard-row treatment:
                        // the control is replaced by a red lock so the setting
                        // can't be turned off mid-block (its whole purpose).
                        HStack {
                            Text("Uninstall Protection")
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("uninstallProtectionLockIcon")
                    } else {
                        Toggle("Uninstall Protection", isOn: uninstallProtectionBinding)
                            .accessibilityIdentifier("uninstallProtectionToggle")
                    }
                } header: {
                    Text("Protection").textCase(nil)
                } footer: {
                    if isUninstallProtectionLocked {
                        Text(
                            "Locked while a Hard Mode rule is actively blocking — Uninstall "
                                + "Protection can't be changed until the block ends.")
                            .accessibilityIdentifier("uninstallProtectionLockedNotice")
                    } else {
                        Text(
                            "While on, apps can't be deleted from this device whenever a "
                                + "Hard Mode rule is actively blocking — so the block can't be "
                                + "removed by uninstalling.")
                    }
                }
                Section {
                    NavigationLink {
                        ManageAppListsView()
                    } label: {
                        Label("Manage App Lists", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("manageAppListsButton")
                } header: {
                    Text("App Lists").textCase(nil)
                }
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("notificationSettingsButton")
                } header: {
                    Text("Notifications").textCase(nil)
                }
                linkSection
                if launch.isUITesting {
                    // Test-only probe: the destination of the last intercepted
                    // link tap, so a UI test can assert the buttons open the
                    // configured URLs without launching Safari.
                    Section {
                        Text(lastOpenedLink?.absoluteString ?? "none")
                            .accessibilityIdentifier("openedLinkProbe")
                    }
                }
            }
            .navigationTitle("Settings")
            .captureLinkTaps(when: launch.isUITesting) { lastOpenedLink = $0 }
        }
        .onAppear {
            uninstallProtectionOn = settings.uninstallProtectionEnabled
        }
    }

    /// "About" section: external links (GitHub repo, marketing site). A link is
    /// omitted when its destination is unconfigured; the whole section is
    /// dropped when neither is set, so no stray header appears.
    @ViewBuilder private var linkSection: some View {
        if gitHubURL != nil || websiteURL != nil {
            Section {
                if let gitHubURL {
                    Link("GitHub", destination: gitHubURL)
                        .accessibilityIdentifier("githubLinkButton")
                }
                if let websiteURL {
                    Link("Website", destination: websiteURL)
                        .accessibilityIdentifier("websiteLinkButton")
                }
            } header: {
                Text("About").textCase(nil)
            }
        }
    }

    /// True while any Hard Mode rule is actively blocking, which locks the
    /// toggle (it must not be turned off while a hard block is in force).
    private var isUninstallProtectionLocked: Bool {
        !RulePolicy.canToggleUninstallProtection(
            rules: rules, usageFor: { enforcer.usage(for: $0) })
    }

    /// Drives the toggle's visual state from `@State` while persisting and
    /// re-enforcing on every change — so protection engages/lifts immediately.
    private var uninstallProtectionBinding: Binding<Bool> {
        Binding(
            get: { uninstallProtectionOn },
            set: { newValue in
                // Defense in depth: the locked row shows no toggle, but never
                // let a write through while a hard block is in force.
                guard !isUninstallProtectionLocked else { return }
                uninstallProtectionOn = newValue
                settings.uninstallProtectionEnabled = newValue
                enforcer.refresh(rules: rules)
            }
        )
    }
}

private extension View {
    /// In UI-testing mode, swallow `Link` activations and report the destination
    /// instead of opening Safari, so a UI test can assert which URL was opened.
    /// A no-op otherwise, so production links open normally.
    @ViewBuilder
    func captureLinkTaps(when active: Bool, perform: @escaping (URL) -> Void) -> some View {
        if active {
            environment(\.openURL, OpenURLAction { url in
                perform(url)
                return .handled
            })
        } else {
            self
        }
    }
}
