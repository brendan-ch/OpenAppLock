//
//  OpenAppLockApp.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2025.08.09.
//

import SwiftData
import SwiftUI

@main
struct OpenAppLockApp: App {
    private let container: ModelContainer
    @State private var authorization: ScreenTimeAuthorization
    @State private var notificationAuthorization: NotificationAuthorization
    @State private var enforcer: RuleEnforcer
    @State private var settings: AppSettingsStore
    @State private var logStore: LogStore

    init() {
        let config = LaunchConfiguration.current

        // Diagnostic logging, configured before anything else can log: app-group
        // `Logs/` in production; a wiped per-launch temp dir under UI testing so
        // the export flow is hermetic and deterministic.
        let logsDirectory: URL
        if config.isUITesting {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("DiagLogsUITest", isDirectory: true)
            try? FileManager.default.removeItem(at: temp)
            logsDirectory = temp
        } else {
            logsDirectory = DiagnosticLogLocation.defaultDirectory()
        }
        Diag.configure(directory: logsDirectory)
        let logStore = LogStore(directory: logsDirectory)
        if !config.isUITesting {
            logStore.prune()
        }
        _logStore = State(initialValue: logStore)
        Diag.log(.lifecycle, "app launch (uiTesting=\(config.isUITesting))")
        if config.seedLogs {
            Diag.log(.rule, "SEED-MARKER seeded rule snapshot")
            Diag.log(.enforcer, .event, "SEED-MARKER refresh applied a shield")
            Diag.error(.monitor, "SEED-MARKER simulated threshold drop")
        }

        if let onboardingCompleted = config.onboardingCompleted {
            UserDefaults.standard.set(onboardingCompleted, forKey: "hasCompletedOnboarding")
        }

        // The app-group suite persists across UI-test launches (unlike the
        // in-memory SwiftData store), so start each UI-test run from a clean
        // Uninstall Protection state.
        if config.isUITesting {
            AppSettingsStore.resetForTesting()
        }
        let appSettings = AppSettingsStore()
        _settings = State(initialValue: appSettings)

        let schema = Schema([BlockingRule.self, AppList.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: config.isUITesting
        )
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        let usageLedger: UsageReading = config.isUITesting ? MockUsageLedger() : UsageLedger()

        if let scenario = config.seedScenario {
            SampleRules.seed(
                scenario, into: container.mainContext, usage: usageLedger as? MockUsageLedger
            )
        }
        AppListMigration.run(in: container.mainContext)

        let authProvider: AuthorizationProviding =
            config.isUITesting
            ? MockAuthorizationProvider(
                status: config.onboardingCompleted == false ? .notDetermined : .approved
            )
            : FamilyControlsAuthorizationProvider()
        _authorization = State(initialValue: ScreenTimeAuthorization(provider: authProvider))

        let notificationProvider: NotificationAuthorizationProviding =
            config.isUITesting
            ? MockNotificationAuthorizationProvider(
                status: config.notificationsAuthorized ? .authorized : .notDetermined)
            : UserNotificationAuthorizationProvider()
        _notificationAuthorization = State(
            initialValue: NotificationAuthorization(
                provider: notificationProvider,
                initialStatus: config.isUITesting && config.notificationsAuthorized
                    ? .authorized : .notDetermined))

        let shields: ShieldApplying =
            config.isUITesting ? MockShieldController() : ManagedSettingsShieldController()
        let scheduler =
            config.isUITesting
            ? nil : RuleScheduler(monitor: DeviceActivityCenterMonitor())
        // Like the DeviceActivity scheduler, the notification scheduler is real
        // only outside UI tests (which must not schedule system notifications).
        let notificationScheduler = config.isUITesting ? nil : NotificationScheduler()
        let openSessions: OpenSessionReading =
            config.isUITesting ? MockOpenSessionStore() : OpenSessionStore()
        _enforcer = State(
            initialValue: RuleEnforcer(
                shields: shields, usage: usageLedger, scheduler: scheduler,
                notificationScheduler: notificationScheduler,
                openSessions: openSessions, settings: appSettings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authorization)
                .environment(notificationAuthorization)
                .environment(enforcer)
                .environment(settings)
                .environment(logStore)
        }
        .modelContainer(container)
    }
}
