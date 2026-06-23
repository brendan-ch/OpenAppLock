//
//  LaunchConfiguration.swift
//  OpenAppLock
//

import Foundation

/// Launch-argument configuration used by UI tests: in-memory storage, mocked
/// Screen Time authorization, forced onboarding state, and seeded scenarios.
struct LaunchConfiguration: Equatable {
    enum SeedScenario: String {
        /// One actively blocking rule ("Work Time") and one upcoming rule ("Sleep").
        case standard
        /// An actively blocking Hard Mode rule ("Locked In") plus an upcoming rule.
        case hardModeActive = "hard-mode-active"
        /// Limit rules with seeded usage: "Time Keeper" (18m of 45m),
        /// "Gate Keeper" (2 of 5 opens), and "Doom Scroll" (budget spent →
        /// blocked until tomorrow).
        case limits
    }

    var isUITesting = false
    /// Forces the onboarding-completed flag at launch. Nil leaves stored state alone.
    var onboardingCompleted: Bool?
    var seedScenario: SeedScenario?
    /// Overrides the Settings GitHub link so UI tests open a known URL instead of
    /// the configured (swappable) build-setting value. Nil uses `AppLinks`.
    var gitHubURLOverride: String?
    /// Overrides the Settings website link for UI tests. Nil uses `AppLinks`.
    var websiteURLOverride: String?
    /// Seeds the mock notification authorization as already-granted, so a UI test
    /// can exercise the authorized state directly. Absent → `.notDetermined`, so
    /// the grant transition is the default path under test.
    var notificationsAuthorized = false
    /// Seeds a few deterministic diagnostic-log entries at launch (UI tests), so
    /// the Settings → Logs export flow has known content to assert against.
    var seedLogs = false

    static let uiTestingFlag = "-ui-testing"
    static let onboardingCompletedFlag = "-onboarding-completed"
    static let onboardingRequiredFlag = "-onboarding-required"
    static let seedScenarioPrefix = "-seed-scenario="
    static let gitHubURLPrefix = "-github-url="
    static let websiteURLPrefix = "-website-url="
    static let notificationsAuthorizedFlag = "-notifications-authorized"
    static let seedLogsFlag = "-seed-logs"

    static func parse(arguments: [String]) -> LaunchConfiguration {
        var config = LaunchConfiguration()
        config.isUITesting = arguments.contains(uiTestingFlag)
        if arguments.contains(onboardingCompletedFlag) {
            config.onboardingCompleted = true
        } else if arguments.contains(onboardingRequiredFlag) {
            config.onboardingCompleted = false
        }
        if let seedArgument = arguments.first(where: { $0.hasPrefix(seedScenarioPrefix) }) {
            config.seedScenario = SeedScenario(
                rawValue: String(seedArgument.dropFirst(seedScenarioPrefix.count))
            )
        }
        config.gitHubURLOverride = value(in: arguments, prefix: gitHubURLPrefix)
        config.websiteURLOverride = value(in: arguments, prefix: websiteURLPrefix)
        config.notificationsAuthorized = arguments.contains(notificationsAuthorizedFlag)
        config.seedLogs = arguments.contains(seedLogsFlag)
        return config
    }

    /// Returns the suffix of the first `prefix=value` argument, or nil if absent.
    private static func value(in arguments: [String], prefix: String) -> String? {
        arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    static let current = parse(arguments: ProcessInfo.processInfo.arguments)
}
