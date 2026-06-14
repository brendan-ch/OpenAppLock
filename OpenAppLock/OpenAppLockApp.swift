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
    @State private var enforcer: RuleEnforcer
    @State private var settings: AppSettingsStore

    init() {
        let config = LaunchConfiguration.current

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

        let shields: ShieldApplying =
            config.isUITesting ? MockShieldController() : ManagedSettingsShieldController()
        let scheduler =
            config.isUITesting
            ? nil : RuleScheduler(monitor: DeviceActivityCenterMonitor())
        let openSessions: OpenSessionReading =
            config.isUITesting ? MockOpenSessionStore() : OpenSessionStore()
        _enforcer = State(
            initialValue: RuleEnforcer(
                shields: shields, usage: usageLedger, scheduler: scheduler,
                openSessions: openSessions, settings: appSettings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authorization)
                .environment(enforcer)
                .environment(settings)
        }
        .modelContainer(container)
    }
}
