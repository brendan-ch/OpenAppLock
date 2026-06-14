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

    static let uiTestingFlag = "-ui-testing"
    static let onboardingCompletedFlag = "-onboarding-completed"
    static let onboardingRequiredFlag = "-onboarding-required"
    static let seedScenarioPrefix = "-seed-scenario="

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
        return config
    }

    static let current = parse(arguments: ProcessInfo.processInfo.arguments)
}
