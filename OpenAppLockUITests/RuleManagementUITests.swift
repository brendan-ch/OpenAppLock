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
        XCTAssertTrue(app.element("detailRow-Unblocks allowed").exists)
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
        XCTAssertEqual(hardMode.label, "Hard Mode", "The Hard Mode switch must carry its label for VoiceOver")
        XCTAssertEqual(hardMode.value as? String, "0", "Hard Mode starts off")

        // A centered `.tap()` lands on the row label and doesn't flip a SwiftUI
        // Toggle; tap the switch itself at the trailing edge. The asserted value
        // change fails loudly here if the tap misses, rather than surfacing later
        // as an unreachable `doneButton`.
        hardMode.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(hardMode.value as? String, "1", "Tapping Hard Mode should turn it on")

        app.buttons["doneButton"].waitToAppear().tap()

        // Back on the detail view, unblocks are no longer allowed.
        let row = app.element("detailRow-Unblocks allowed").waitToAppear()
        XCTAssertTrue(row.label.contains("No"), "Expected 'Unblocks allowed: No', got: \(row.label)")
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
        XCTAssertTrue(app.element("detailRow-Unblocks allowed").label.contains("No"))
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
