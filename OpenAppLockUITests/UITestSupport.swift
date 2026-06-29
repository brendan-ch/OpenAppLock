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
        websiteURL: String? = nil,
        notificationsAuthorized: Bool = false
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
        if notificationsAuthorized {
            arguments.append("-notifications-authorized")
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
    ///
    /// Each section's detail names its navigation bar after the same label as the
    /// tab/row (`navigationTitle("Rules")` → `navigationBars["Rules"]`), giving a
    /// device-agnostic "we actually landed" post-condition.
    private func goToSection(
        tabLabel: String, sidebarIdentifier: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let tab = tabBars.buttons[tabLabel]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
            return
        }

        // iPad sidebar (NavigationSplitView). A single synthesized tap on a
        // selection-driven sidebar row is occasionally dropped before the app has
        // quiesced — the row never becomes selected and the detail stays on the
        // previous section, so a following content assertion flakes. Confirm the
        // target section's detail actually appeared and re-tap if it didn't,
        // rather than assuming the first tap took.
        let item = element(sidebarIdentifier).waitToAppear(file: file, line: line)
        let sectionBar = navigationBars[tabLabel]
        for _ in 0..<5 {
            item.tap()
            if sectionBar.waitForExistence(timeout: 2) { return }
        }
        XCTAssertTrue(
            sectionBar.exists,
            "Sidebar navigation to \(tabLabel) never landed after repeated taps",
            file: file, line: line
        )
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

    /// Polls until the element's `label` equals `expected`, then returns it.
    /// Use instead of reading `.label` straight after an action that updates it
    /// asynchronously (e.g. a SwiftUI re-render after `typeText`): on a slow CI
    /// runner the label lags the action, and a bare `XCTAssertEqual` races it.
    @discardableResult
    func waitForLabel(
        _ expected: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected), object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "Expected label \"\(expected)\" within \(timeout)s, got \"\(label)\"",
            file: file, line: line)
        return self
    }
}
