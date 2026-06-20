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

    func testUninstallProtectionLockedDuringHardSession() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToSettingsTab()

        // While the seeded "Locked In" Hard Mode rule is blocking, the toggle is
        // replaced by a lock (mirroring Home's "Currently Blocking" rows) so the
        // protection can't be turned off mid-block.
        app.element("uninstallProtectionLockedNotice").waitToAppear()
        app.element("uninstallProtectionLockIcon").waitToAppear()
        XCTAssertFalse(
            app.switches["uninstallProtectionToggle"].exists,
            "The Uninstall Protection switch must be hidden while a Hard Mode rule is blocking"
        )
    }

    func testManageAppListsCreateFlow() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToSettingsTab()

        app.element("manageAppListsButton").waitToAppear().tap()

        // Fresh install: no lists yet — the same create flow as the rule editor.
        app.element("emptyAppListsLabel").waitToAppear()
        app.buttons["newAppListButton"].tap()

        // The list editor opens as a sheet overlay.
        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Distractions\n")
        app.element("emptySelectionLabel").waitToAppear()

        // The editor's checkmark saves and dismisses the overlay.
        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Saving returns to the management list with the new list present.
        app.element("appListRow-Distractions").waitToAppear()

        // Management rows open the editor overlay on tap (no separate Edit button).
        app.element("appListRow-Distractions").tap()
        XCTAssertTrue(
            app.textFields["appListNameField"].waitToAppear().exists,
            "Tapping a list in management mode should open it for editing"
        )
    }

    func testAboutLinksOpenConfiguredURLs() throws {
        let gitHub = "https://example.com/openapplock-repo"
        let website = "https://example.com/openapplock-site"
        let app = XCUIApplication.launchOpenAppLock(gitHubURL: gitHub, websiteURL: website)
        app.goToSettingsTab()

        // In UI-testing mode link taps are intercepted (no Safari launch) and the
        // last-opened URL is reflected into `openedLinkProbe`, so we can assert
        // each button opens the URL the app was configured with.
        let probe = app.staticTexts["openedLinkProbe"].waitToAppear()
        XCTAssertEqual(probe.label, "none", "No link should have been opened yet")

        app.element("githubLinkButton").waitToAppear().tap()
        expectation(for: NSPredicate(format: "label == %@", gitHub), evaluatedWith: probe)
        waitForExpectations(timeout: 3)

        app.element("websiteLinkButton").waitToAppear().tap()
        expectation(for: NSPredicate(format: "label == %@", website), evaluatedWith: probe)
        waitForExpectations(timeout: 3)
    }

    func testManageAppListsLockedDuringHardSession() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToSettingsTab()

        app.element("manageAppListsButton").waitToAppear().tap()

        // The seeded "Distractions" list is visible but read-only while the
        // hard-mode rule is blocking — same lock as the rule editor's picker.
        app.element("appListRow-Distractions").waitToAppear()
        app.element("appListsLockedNotice").waitToAppear()
        // Management mode edits via row tap; while locked, the tap must do nothing.
        app.element("appListRow-Distractions").tap()
        XCTAssertFalse(
            app.textFields["appListNameField"].waitForExistence(timeout: 1.5),
            "App lists must be read-only while a Hard Mode rule is blocking"
        )
    }
}
