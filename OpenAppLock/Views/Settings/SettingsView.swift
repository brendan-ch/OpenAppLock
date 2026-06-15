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
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            uninstallProtectionOn = settings.uninstallProtectionEnabled
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
