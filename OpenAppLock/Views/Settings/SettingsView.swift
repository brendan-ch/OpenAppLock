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
                    Toggle("Uninstall Protection", isOn: uninstallProtectionBinding)
                        .accessibilityIdentifier("uninstallProtectionToggle")
                } header: {
                    Text("Protection").textCase(nil)
                } footer: {
                    Text(
                        "While on, apps can't be deleted from this device whenever a "
                            + "Hard Mode rule is actively blocking — so the block can't be "
                            + "removed by uninstalling.")
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

    /// Drives the toggle's visual state from `@State` while persisting and
    /// re-enforcing on every change — so protection engages/lifts immediately.
    private var uninstallProtectionBinding: Binding<Bool> {
        Binding(
            get: { uninstallProtectionOn },
            set: { newValue in
                uninstallProtectionOn = newValue
                settings.uninstallProtectionEnabled = newValue
                enforcer.refresh(rules: rules)
            }
        )
    }
}
