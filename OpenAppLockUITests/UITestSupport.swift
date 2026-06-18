//
//  UITestSupport.swift
//  OpenAppLockUITests
//

import XCTest

extension XCUIApplication {
    /// Launches the app in UI-testing mode: in-memory storage, mocked Screen
    /// Time authorization, and no shield side effects.
    ///
    /// `gitHubURL` / `websiteURL` override the configured Settings links with
    /// deterministic values, so link tests don't depend on the committed build
    /// settings (which point at the real, swappable destinations).
    static func launchOpenAppLock(
        onboardingCompleted: Bool = true,
        seedScenario: String? = nil,
        gitHubURL: String? = nil,
        websiteURL: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ui-testing"]
        arguments.append(onboardingCompleted ? "-onboarding-completed" : "-onboarding-required")
        if let seedScenario {
            arguments.append("-seed-scenario=\(seedScenario)")
        }
        if let gitHubURL {
            arguments.append("-github-url=\(gitHubURL)")
        }
        if let websiteURL {
            arguments.append("-website-url=\(websiteURL)")
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

extension XCUIApplication {
    /// Finds an element by accessibility identifier regardless of how SwiftUI
    /// exposes it (Other, StaticText, Button, …).
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIApplication {
    /// Switches to the Home section (Currently Blocking + Usage). Home is the
    /// default selection, so most Home tests don't need to call this.
    func goToHomeTab() { goToSection(tabLabel: "Home", sidebarIdentifier: "sidebarItem-home") }
    /// Switches to the Rules section (the rule list + New Rule button).
    func goToRulesTab() { goToSection(tabLabel: "Rules", sidebarIdentifier: "sidebarItem-rules") }
    /// Switches to the Settings section (Uninstall Protection + Manage App Lists).
    func goToSettingsTab() { goToSection(tabLabel: "Settings", sidebarIdentifier: "sidebarItem-settings") }

    /// Navigates to a top-level section regardless of the current navigation
    /// chrome: the bottom tab bar in compact width (iPhone, iPad multitasking) or
    /// the left sidebar in regular width (full-screen iPad). Keeps the rest of the
    /// UI suite agnostic to which device it runs on.
    private func goToSection(tabLabel: String, sidebarIdentifier: String) {
        let tab = tabBars.buttons[tabLabel]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            element(sidebarIdentifier).waitToAppear().tap()
        }
    }

    /// Waits for the post-onboarding shell to appear in whichever chrome the
    /// device presents — the bottom tab bar on iPhone, the left sidebar on
    /// full-screen iPad — so tests can confirm "we reached the main app" without
    /// hard-coding one device's navigation.
    @discardableResult
    func waitForMainUI() -> XCUIApplication {
        if UIDevice.current.userInterfaceIdiom == .pad {
            element("sidebarItem-home").waitToAppear()
        } else {
            tabBars.buttons["Home"].waitToAppear()
        }
        return self
    }
}

extension XCUIElement {
    /// Asserts the element appears within the timeout, then returns it.
    @discardableResult
    func waitToAppear(
        timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            waitForExistence(timeout: timeout),
            "Expected \(self) to exist within \(timeout)s",
            file: file, line: line
        )
        return self
    }
}
