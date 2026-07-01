//
//  NotificationSettingsView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Notifications sub-page of Settings: grant local-notification permission
/// and toggle the two opt-in notification types.
///
/// - **Schedule starting soon** — a local notification ~5 minutes before a
///   Schedule rule's window begins (pre-scheduled calendar triggers).
/// - **Time limit almost up** — a notification when a Time-Limit rule has ~5
///   minutes of its daily allowance left (posted by the monitor extension when a
///   dedicated warn event fires).
///
/// Both toggles are disabled until permission is granted; each type only
/// delivers while authorization holds (the effective gate ANDs the toggle with
/// authorization — see ``NotificationPreferences``). Flipping a toggle, or
/// granting permission, re-runs `RuleEnforcer.refresh` so the scheduling for
/// both mechanisms updates immediately.
struct NotificationSettingsView: View {
    @Environment(NotificationAuthorization.self) private var authorization
    @Environment(AppSettingsStore.self) private var settings
    @Environment(RuleEnforcer.self) private var enforcer
    @Environment(\.openURL) private var openURL
    @Query private var rules: [BlockingRule]

    var body: some View {
        List {
            permissionSection
            typesSection
        }
        .navigationTitle(CopyKey.notificationsNavigationTitle.resource)
        .navigationBarTitleDisplayMode(.inline)
        // Pick up changes the user made in the system Settings app (including a
        // revocation, which surfaces the denied state and disables delivery).
        .task { await authorization.refresh() }
    }

    @ViewBuilder private var permissionSection: some View {
        Section {
            switch authorization.status {
            case .authorized:
                HStack {
                    Label(
                        CopyKey.notificationsAllowedStatusLabel.resource,
                        systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("notificationStatusLabel")
            case .notDetermined:
                Button(CopyKey.notificationsAllowButton.resource) {
                    Task {
                        await authorization.request()
                        enforcer.refresh(rules: rules)
                    }
                }
                .accessibilityIdentifier("allowNotificationsButton")
            case .denied:
                Button(CopyKey.notificationsOpenSettingsButton.resource) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .accessibilityIdentifier("openNotificationSettingsButton")
            }
        } header: {
            Text(.notificationsPermissionSectionHeader).textCase(nil)
        } footer: {
            if authorization.status == .denied {
                Text(.notificationsDeniedFooter)
            }
        }
    }

    @ViewBuilder private var typesSection: some View {
        Section {
            Toggle(
                CopyKey.notificationsScheduleStartToggleLabel.resource,
                isOn: toggleBinding(\.notifyScheduleStartEnabled))
                .accessibilityIdentifier("scheduleStartNotificationToggle")
                .disabled(!isAuthorized)
            Toggle(
                CopyKey.notificationsTimeLimitToggleLabel.resource,
                isOn: toggleBinding(\.notifyTimeLimitEndingEnabled))
                .accessibilityIdentifier("timeLimitNotificationToggle")
                .disabled(!isAuthorized)
        } header: {
            Text(.notificationsNotifyMeSectionHeader).textCase(nil)
        } footer: {
            Text(.notificationsFooter)
        }
    }

    private var isAuthorized: Bool { authorization.status == .authorized }

    /// A binding that writes the toggle through to the store and re-enforces, so
    /// the schedule-start notifications and the time-limit warn activity update
    /// in one step.
    private func toggleBinding(
        _ keyPath: ReferenceWritableKeyPath<AppSettingsStore, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                enforcer.refresh(rules: rules)
            })
    }
}

#Preview("Authorized") {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(
        NotificationAuthorization(
            provider: MockNotificationAuthorizationProvider(status: .authorized),
            initialStatus: .authorized))
    .environment(AppSettingsStore())
    .environment(RuleEnforcer(shields: MockShieldController()))
    .modelContainer(for: [BlockingRule.self, AppList.self], inMemory: true)
}

#Preview("Permission not yet granted") {
    NavigationStack {
        NotificationSettingsView()
    }
    .environment(
        NotificationAuthorization(
            provider: MockNotificationAuthorizationProvider(status: .notDetermined),
            initialStatus: .notDetermined))
    .environment(AppSettingsStore())
    .environment(RuleEnforcer(shields: MockShieldController()))
    .modelContainer(for: [BlockingRule.self, AppList.self], inMemory: true)
}
