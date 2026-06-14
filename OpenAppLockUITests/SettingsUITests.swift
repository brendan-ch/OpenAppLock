//
//  SettingsUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The Settings tab: the Uninstall Protection toggle and the Manage App Lists
/// flow (which reuses the rule editor's app-list library, minus selection).
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUninstallProtectionToggleStartsOffAndFlips() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToSettingsTab()

        let toggle = app.switches["uninstallProtectionToggle"].waitToAppear()
        XCTAssertEqual(toggle.value as? String, "0", "Uninstall Protection should default off")
        // `.tap()` lands on the element's center (over the label) and doesn't
        // reliably flip a SwiftUI switch — tap the control itself.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1", "Tapping should turn it on")
    }

    func testManageAppListsCreateFlow() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToSettingsTab()

        app.element("manageAppListsButton").waitToAppear().tap()

        // Fresh install: no lists yet — the same create flow as the rule editor.
        app.element("emptyAppListsLabel").waitToAppear()
        app.buttons["newAppListButton"].tap()

        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Distractions\n")

        app.element("emptySelectionLabel").waitToAppear()
        app.buttons["editAppsButton"].tap()
        app.element("selectionCountLabel").waitToAppear()
        app.buttons["confirmSelectionButton"].tap()

        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Saving returns to the management list with the new list present.
        app.element("appListRow-Distractions").waitToAppear()
    }

    func testManageAppListsLockedDuringHardSession() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToSettingsTab()

        app.element("manageAppListsButton").waitToAppear().tap()

        // The seeded "Distractions" list is visible but read-only while the
        // hard-mode rule is blocking — same lock as the rule editor's picker.
        app.element("appListRow-Distractions").waitToAppear()
        app.element("appListsLockedNotice").waitToAppear()
        XCTAssertFalse(
            app.buttons["editAppListButton-Distractions"].exists,
            "App lists must be read-only while a Hard Mode rule is blocking"
        )
    }
}
