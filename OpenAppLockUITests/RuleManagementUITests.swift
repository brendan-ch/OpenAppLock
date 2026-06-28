//
//  RuleManagementUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// Detail sheet, editing, disabling, deleting, and unblocking — seeded with
/// one actively-blocking rule ("Work Time") and one upcoming rule ("Sleep").
/// Rule cards live on the Rules tab; blocked tiles on the Home tab.
final class RuleManagementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDetailShowsLiveStatusAndFacts() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Work Time"].waitToAppear().tap()

        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Work Time")
        XCTAssertTrue(app.staticTexts["detailStatusLabel"].label.contains("left"))
        app.element("detailRow-During this time").waitToAppear()
        XCTAssertTrue(app.element("detailRow-On these days").exists)
        XCTAssertTrue(app.element("detailRow-Pausing allowed").exists)
        app.buttons["editRuleButton"].waitToAppear()

        app.buttons["closeDetailButton"].tap()
        app.buttons["newRuleButton"].waitToAppear()
    }

    func testEditRuleTogglesHardModeOn() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // On iPad the editor is a shorter, centered form sheet; the Hard Mode row
        // can start below the fold and isn't rendered until scrolled into view.
        let hardMode = app.switches["hardModeToggle"]
        if !hardMode.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        hardMode.waitToAppear()
        XCTAssertEqual(hardMode.label, "Hard Mode", "The Hard Mode switch must carry its label for VoiceOver")
        // A labeled Toggle fills the row, so a centered `.tap()` lands on the
        // label; tap the switch itself at the trailing edge to flip it.
        hardMode.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["doneButton"].tap()

        // Back on the detail view, pausing is no longer allowed.
        let row = app.element("detailRow-Pausing allowed").waitToAppear()
        XCTAssertTrue(row.label.contains("No"), "Expected 'Pausing allowed: No', got: \(row.label)")
    }

    func testDisableRule() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // Disable lives in the ellipsis menu in the navigation bar.
        let actionsMenu = app.navigationBars.buttons["ruleActionsMenu"].waitToAppear()
        XCTAssertEqual(actionsMenu.label, "Rule Actions")
        actionsMenu.tap()
        app.buttons["Disable Rule"].waitToAppear().tap()

        // The detail caption now reports the rule as disabled.
        let status = app.staticTexts["detailStatusLabel"].waitToAppear()
        XCTAssertTrue(status.label.contains("Disabled"), "Got: \(status.label)")

        app.buttons["closeDetailButton"].tap()
        let cardStatus = app.staticTexts["ruleStatus-Sleep"].waitToAppear()
        XCTAssertEqual(cardStatus.label, "Disabled")
    }

    func testDeleteRuleRemovesCard() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // Delete lives in the ellipsis menu in the navigation bar.
        app.navigationBars.buttons["ruleActionsMenu"].waitToAppear().tap()
        app.buttons["Delete Rule"].waitToAppear().tap()

        app.buttons["newRuleButton"].waitToAppear()
        XCTAssertFalse(
            app.buttons["ruleCard-Sleep"].waitForExistence(timeout: 2),
            "Deleted rule's card should disappear"
        )
        XCTAssertTrue(app.buttons["ruleCard-Work Time"].exists)
    }

    func testUnblockActiveSoftRule() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")

        // The active rule surfaces in Currently Blocking (Home tab); unblocking pauses it.
        app.buttons["blockedTile-Work Time"].waitToAppear().tap()
        app.sheets.buttons["Unblock"].waitToAppear().tap()

        app.staticTexts["nothingBlockedLabel"].waitToAppear()
        // The paused state shows on the rule's card over on the Rules tab.
        app.goToRulesTab()
        XCTAssertEqual(app.staticTexts["ruleStatus-Work Time"].waitToAppear().label, "Paused")
    }

    func testPauseActiveSoftRuleFromDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Work Time"].waitToAppear().tap()

        app.buttons["pauseRuleButton"].waitToAppear().tap()
        // The confirmation dialog's button shares the row label, so scope to the sheet.
        app.sheets.buttons["Pause for 15 minutes"].waitToAppear().tap()

        // Paused → Resume replaces Pause, and the status reads a resume countdown.
        app.buttons["resumeRuleButton"].waitToAppear()
        XCTAssertTrue(app.staticTexts["detailStatusLabel"].label.contains("Resumes in"))

        // Resume re-blocks immediately.
        app.buttons["resumeRuleButton"].tap()
        app.buttons["pauseRuleButton"].waitToAppear()
    }
}

/// Hard block behavior — seeded with an actively-blocking Hard Mode rule.
final class HardModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHardLockedRuleCannotBeEdited() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToRulesTab()

        app.buttons["ruleCard-Locked In"].waitToAppear().tap()

        // The lock notice replaces Edit Rule entirely.
        app.element("hardModeLockedNotice").waitToAppear()
        XCTAssertFalse(app.buttons["editRuleButton"].exists)
        XCTAssertTrue(app.element("detailRow-Pausing allowed").label.contains("No"))
    }

    func testHardLockedRuleCannotBeUnblocked() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")

        // The hard rule shows a lock (not an Unblock button) in Currently Blocking;
        // tapping the row still explains why it can't be lifted.
        app.buttons["blockedTile-Locked In"].waitToAppear().tap()

        // No unblock dialog — just the refusal alert.
        let alert = app.alerts["Hard Mode is on"].waitToAppear()
        XCTAssertTrue(alert.staticTexts["This block can't be lifted until it ends."].exists)
        alert.buttons["OK"].tap()

        // Still blocked.
        XCTAssertTrue(app.buttons["blockedTile-Locked In"].exists)
        XCTAssertFalse(app.staticTexts["nothingBlockedLabel"].exists)
    }

    func testSoftRuleUnblockOfferedButHardRuleRefused() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")

        app.buttons["blockedTile-Work Time"].waitToAppear().tap()
        // Soft rule: the confirmation dialog appears instead of the refusal alert.
        app.sheets.buttons["Unblock"].waitToAppear()
        XCTAssertFalse(app.alerts["Hard Mode is on"].exists)
    }
}
