//
//  AppListUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// App lists: the editor's App List row, the picker (select / create / edit),
/// rule-level Block vs Allow Only, and the Hard Mode list lockdown. The rule
/// editor (and its app-list picker) is reached from the Rules tab.
final class AppListUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testScheduleEditorOffersModeChoice() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()

        app.staticTexts["ruleEditorTitle"].waitToAppear()
        app.swipeUp()
        app.element("selectionModePicker").waitToAppear()
        XCTAssertTrue(app.staticTexts["Apps are blocked"].exists)
    }

    func testLimitEditorsAreBlockOnly() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()

        app.buttons["ruleKind-timeLimit"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear()
        XCTAssertFalse(
            app.element("selectionModePicker").exists,
            "Time-limit rules are always Block; the mode picker must not appear"
        )

        // Back to the rule-type list, then check the open-limit editor too.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: middle)

        app.buttons["ruleKind-openLimit"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear()
        XCTAssertFalse(app.element("selectionModePicker").exists)
    }

    func testCreateAppListFlowSelectsNewList() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-timeLimit"].waitToAppear().tap()

        app.element("selectedAppsRow").waitToAppear().tap()

        // Fresh install: no lists yet, so the picker offers creation.
        app.element("emptyAppListsLabel").waitToAppear()
        app.buttons["newAppListButton"].tap()

        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Focus Apps\n")

        // Screen 1 lists the (empty) selection; Edit Apps pushes the Screen
        // Time picker, whose Save returns here.
        app.element("emptySelectionLabel").waitToAppear()
        app.buttons["editAppsButton"].tap()
        app.element("selectionCountLabel").waitToAppear()
        app.buttons["confirmSelectionButton"].tap()

        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Saving pops back to the picker with the new list selected.
        app.element("appListRow-Focus Apps").waitToAppear()
        app.buttons["closeAppListPickerButton"].tap()

        // The editor row now reports the chosen list.
        let row = app.element("selectedAppsRow").waitToAppear()
        XCTAssertTrue(row.label.contains("Focus Apps"), "Got: \(row.label)")
    }

    func testDetailShowsAppListName() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Work Time"].waitToAppear().tap()

        let row = app.element("detailRow-Block").waitToAppear()
        XCTAssertTrue(row.label.contains("Distractions"), "Got: \(row.label)")
    }

    func testHardModeSessionLocksAppListEditing() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToRulesTab()

        // "Sleep" is soft and editable even while "Locked In" hard-blocks.
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear().tap()

        app.element("appListRow-Distractions").waitToAppear()
        app.element("appListsLockedNotice").waitToAppear()
        XCTAssertFalse(
            app.buttons["editAppListButton-Distractions"].exists,
            "App lists must be read-only while a Hard Mode rule is blocking"
        )
    }

    func testAppListsEditableWithoutHardSession() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear().tap()

        app.buttons["editAppListButton-Distractions"].waitToAppear()
        XCTAssertFalse(app.element("appListsLockedNotice").exists)
    }
}
