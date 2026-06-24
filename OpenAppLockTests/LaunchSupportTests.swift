//
//  LaunchSupportTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Launch configuration parsing")
struct LaunchConfigurationTests {
    @Test("Defaults are production settings")
    func defaults() {
        let config = LaunchConfiguration.parse(arguments: ["OpenAppLockApp"])
        #expect(!config.isUITesting)
        #expect(config.onboardingCompleted == nil)
        #expect(config.seedScenario == nil)
    }

    @Test("UI testing flags are recognized")
    func uiTestingFlags() {
        let config = LaunchConfiguration.parse(arguments: [
            "OpenAppLockApp", "-ui-testing", "-onboarding-completed", "-seed-scenario=standard",
        ])
        #expect(config.isUITesting)
        #expect(config.onboardingCompleted == true)
        #expect(config.seedScenario == .standard)
    }

    @Test("Onboarding can be forced on")
    func onboardingRequired() {
        let config = LaunchConfiguration.parse(arguments: ["OpenAppLockApp", "-onboarding-required"])
        #expect(config.onboardingCompleted == false)
    }

    @Test("Unknown seed scenarios are ignored")
    func unknownScenario() {
        let config = LaunchConfiguration.parse(arguments: ["OpenAppLockApp", "-seed-scenario=nope"])
        #expect(config.seedScenario == nil)
    }

    @Test("Link overrides are parsed from their prefixed arguments")
    func linkOverrides() {
        let config = LaunchConfiguration.parse(arguments: [
            "OpenAppLockApp",
            "-github-url=https://example.com/repo",
            "-website-url=https://example.com/site",
        ])
        #expect(config.gitHubURLOverride == "https://example.com/repo")
        #expect(config.websiteURLOverride == "https://example.com/site")
    }

    @Test("Link overrides default to nil when absent")
    func linkOverridesDefaultNil() {
        let config = LaunchConfiguration.parse(arguments: ["OpenAppLockApp"])
        #expect(config.gitHubURLOverride == nil)
        #expect(config.websiteURLOverride == nil)
    }

    @Test("Parses the -seed-logs flag")
    func parsesSeedLogs() {
        let on = LaunchConfiguration.parse(arguments: [
            "OpenAppLockApp", "-ui-testing", "-seed-logs",
        ])
        #expect(on.seedLogs == true)
        let off = LaunchConfiguration.parse(arguments: ["OpenAppLockApp", "-ui-testing"])
        #expect(off.seedLogs == false)
    }
}

@MainActor
@Suite("Seeded sample rules")
struct SampleRulesTests {
    @Test(
        "Seeded active rules are genuinely active at any time of day",
        arguments: [(0, 30), (9, 0), (12, 30), (23, 50)]
    )
    func activeRuleIsActive(hour: Int, minute: Int) {
        let now = date(2025, 1, 6, hour, minute)
        let rule = SampleRules.activeRule(named: "Work Time", hardMode: false, now: now, calendar: utc)
        #expect(rule.dto.status(at: now, calendar: utc).isActive)
    }

    @Test(
        "Seeded upcoming rules are not active but will start",
        arguments: [(0, 30), (9, 0), (12, 30), (23, 50)]
    )
    func upcomingRuleIsUpcoming(hour: Int, minute: Int) {
        let now = date(2025, 1, 6, hour, minute)
        let rule = SampleRules.upcomingRule(named: "Sleep", now: now, calendar: utc)
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(!status.isActive)
        if case .upcoming = status {} else {
            Issue.record("Expected upcoming, got \(status)")
        }
    }

    @Test("Hard mode scenario seeds a locked active rule")
    func hardModeScenario() {
        let now = date(2025, 1, 6, 12, 0)
        let rule = SampleRules.activeRule(named: "Locked In", hardMode: true, now: now, calendar: utc)
        #expect(RulePolicy.isHardLocked(rule.dto, at: now, calendar: utc))
    }

    @Test("Mock authorization approves on request")
    func mockAuthorization() async {
        let provider = MockAuthorizationProvider()
        let auth = ScreenTimeAuthorization(provider: provider)
        #expect(auth.status == .notDetermined)
        await auth.request()
        #expect(auth.status == .approved)
        #expect(!auth.lastRequestFailed)
    }

    @Test("Mock authorization can simulate denial")
    func mockAuthorizationDenied() async {
        let provider = MockAuthorizationProvider(requestShouldFail: true)
        let auth = ScreenTimeAuthorization(provider: provider)
        await auth.request()
        #expect(auth.status == .denied)
        #expect(auth.lastRequestFailed)
    }
}
