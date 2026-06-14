//
//  UITestSupport.swift
//  OpenAppLockUITests
//

import XCTest

extension XCUIApplication {
    /// Launches the app in UI-testing mode: in-memory storage, mocked Screen
    /// Time authorization, and no shield side effects.
    static func launchOpenAppLock(
        onboardingCompleted: Bool = true,
        seedScenario: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ui-testing"]
        arguments.append(onboardingCompleted ? "-onboarding-completed" : "-onboarding-required")
        if let seedScenario {
            arguments.append("-seed-scenario=\(seedScenario)")
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
    /// Switches to the Home tab (Currently Blocking + Usage). Home is the
    /// default selection, so most Home-tab tests don't need to call this.
    func goToHomeTab() { tabBars.buttons["Home"].waitToAppear().tap() }
    /// Switches to the Rules tab (the rule list + New Rule button).
    func goToRulesTab() { tabBars.buttons["Rules"].waitToAppear().tap() }
    /// Switches to the Settings tab (Uninstall Protection + Manage App Lists).
    func goToSettingsTab() { tabBars.buttons["Settings"].waitToAppear().tap() }
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
