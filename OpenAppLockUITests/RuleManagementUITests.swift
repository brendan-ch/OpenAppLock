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
        // Kind and the live status moved off the navigation title into General rows.
        let kind = app.element("detailRow-Kind").waitToAppear()
        XCTAssertTrue(kind.label.contains("Schedule"), "Got: \(kind.label)")
        let status = app.element("detailRow-Status")
        XCTAssertTrue(status.label.contains("Ends in"), "Got: \(status.label)")
        app.element("detailRow-Timeframe").waitToAppear()
        XCTAssertTrue(app.element("detailRow-Days").exists)
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

        // Wait for the editor to render the Hard Mode row, then scroll it into
        // view only if it is actually below the fold. (The previous
        // `waitForExistence(timeout: 2)` gate could flake `false` on a slow runner
        // before the editor had rendered and trigger a spurious `swipeUp()`, which
        // destabilized the iPad form sheet and made the next tap dismiss it.)
        let hardMode = app.switches["hardModeToggle"].waitToAppear()
        if !hardMode.isHittable {
            app.swipeUp()
            hardMode.waitToAppear()
        }
        XCTAssertEqual(hardMode.label, "Lock while blocking", "The Lock while blocking switch must carry its label for VoiceOver")
        XCTAssertEqual(hardMode.value as? String, "0", "Hard Mode starts off")

        // A centered `.tap()` lands on the row label and doesn't flip a SwiftUI
        // Toggle; tap the switch itself at the trailing edge. The asserted value
        // change fails loudly here if the tap misses, rather than surfacing later
        // as an unreachable `doneButton`.
        hardMode.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(hardMode.value as? String, "1", "Tapping Hard Mode should turn it on")

        app.buttons["doneButton"].waitToAppear().tap()

        // Back on the detail view, pausing is no longer allowed.
        let row = app.element("detailRow-Pausing allowed").waitToAppear()
        XCTAssertTrue(row.label.contains("No"), "Expected 'Pausing allowed: No', got: \(row.label)")
    }

    func testEditingRuleAndClosingWithChangesPromptsToDiscard() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // Make an outstanding edit by renaming the rule (submit to drop the
        // keyboard, which otherwise interferes with resolving the dialog).
        let nameField = app.textFields["ruleNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText(" Edited\n")

        // Closing the editor with unsaved edits confirms before discarding.
        app.buttons["closeDetailButton"].waitToAppear().tap()
        app.buttons["Discard Changes"].waitToAppear().tap()

        // Discarding fades back to the detail with the original name intact —
        // the editor cross-fades in place, it never pushed a separate screen.
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Sleep")
        app.buttons["editRuleButton"].waitToAppear()
    }

    func testEditingRuleAndClosingWithoutChangesSkipsPrompt() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // Enter and leave the editor without touching anything.
        app.textFields["ruleNameField"].waitToAppear()
        app.buttons["closeDetailButton"].waitToAppear().tap()

        // No outstanding edits, so it fades straight back — no discard prompt.
        XCTAssertFalse(
            app.buttons["Discard Changes"].waitForExistence(timeout: 1.5),
            "Closing an unedited rule editor must not prompt to discard"
        )
        app.buttons["editRuleButton"].waitToAppear()
    }

    func testDisableRule() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()

        // Disable lives in the detail overlay's ellipsis options menu.
        let actionsMenu = app.navigationBars.buttons["ruleActionsMenu"].waitToAppear()
        XCTAssertEqual(actionsMenu.label, "Rule Actions")
        actionsMenu.tap()
        app.buttons["Disable"].waitToAppear().tap()

        // The detail's Status row now reports the rule as disabled (polled — the
        // row's label re-renders asynchronously after the menu action).
        app.element("detailRow-Status").waitForLabel(containing: "Disabled")

        app.buttons["closeDetailButton"].tap()
        let cardStatus = app.staticTexts["ruleStatus-Sleep"].waitToAppear()
        XCTAssertEqual(cardStatus.label, "Disabled")
    }

    func testDeleteRuleRemovesCard() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()

        // Delete lives in the detail overlay's ellipsis options menu and now
        // confirms before removing the rule.
        app.navigationBars.buttons["ruleActionsMenu"].waitToAppear().tap()
        app.buttons["deleteRuleButton"].waitToAppear().tap()
        app.sheets.buttons["Delete"].waitToAppear().tap()

        app.buttons["newRuleButton"].waitToAppear()
        XCTAssertFalse(
            app.buttons["ruleCard-Sleep"].waitForExistence(timeout: 2),
            "Deleted rule's card should disappear"
        )
        XCTAssertTrue(app.buttons["ruleCard-Work Time"].exists)
    }

    func testCurrentlyBlockingRowOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")

        // The blocking rule's Home row now navigates to the detail overlay,
        // whose options menu offers Pause — no inline unblock dialog.
        app.buttons["blockedTile-Work Time"].waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Work Time")
        app.navigationBars.buttons["ruleActionsMenu"].waitToAppear().tap()
        app.buttons["pauseRuleButton"].waitToAppear()
    }

    func testPauseActiveSoftRuleFromDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Work Time"].waitToAppear().tap()

        // Pause lives in the options menu; its confirmation shares the row label.
        app.navigationBars.buttons["ruleActionsMenu"].waitToAppear().tap()
        app.buttons["pauseRuleButton"].waitToAppear().tap()
        app.sheets.buttons["Pause for 15 minutes"].waitToAppear().tap()

        // Paused → the Status row reads a resume countdown and the menu offers Resume
        // (polled — the row's label re-renders asynchronously after the dialog).
        app.element("detailRow-Status").waitForLabel(containing: "Resumes in")
        app.navigationBars.buttons["ruleActionsMenu"].tap()
        app.buttons["resumeRuleButton"].waitToAppear().tap()

        // Resume re-blocks immediately, so Pause is offered again.
        app.navigationBars.buttons["ruleActionsMenu"].waitToAppear().tap()
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

    func testHardLockedBlockingRowOffersNoPause() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")

        // The hard rule's Home row opens the detail overlay, which shows the
        // lock notice and hides the options menu (so no Pause/Resume).
        app.buttons["blockedTile-Locked In"].waitToAppear().tap()
        app.element("hardModeLockedNotice").waitToAppear()
        XCTAssertFalse(app.buttons["ruleActionsMenu"].exists)
        XCTAssertFalse(app.buttons["pauseRuleButton"].exists)
        XCTAssertFalse(app.buttons["resumeRuleButton"].exists)
    }
}
