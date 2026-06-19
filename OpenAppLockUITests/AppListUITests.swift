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

        // Back to the rule-type list, then check the open-limit editor too. Use
        // the nav back button rather than an edge-swipe, which assumes a full-width
        // sheet and misses iPad's centered form sheet. Target the back button by
        // its identifier ("BackButton") — its "New Rule" label collides with the
        // Rules tab's "New Rule" (+) button sitting behind the sheet.
        app.navigationBars.buttons["BackButton"].waitToAppear().tap()

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
        // Editing is locked, but the list can still be opened to view its apps.
        XCTAssertTrue(
            app.buttons["viewAppListButton-Distractions"].exists,
            "Locked lists must still offer a read-only View affordance"
        )
    }

    func testHardModeAllowsViewingAppListAppsReadOnly() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToSettingsTab()
        app.buttons["manageAppListsButton"].waitToAppear().tap()

        // The library is locked while "Locked In" hard-blocks ...
        app.element("appListsLockedNotice").waitToAppear()
        // ... yet tapping a list opens it for read-only viewing.
        app.element("appListRow-Distractions").waitToAppear().tap()

        assertReadOnlyDetail(app)
    }

    func testHardModeViewFromPickerOpensReadOnlyDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")
        app.goToRulesTab()

        // Soft "Sleep" is still editable, so its app-list picker is reachable
        // while "Locked In" hard-blocks — but every list inside it is locked.
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear().tap()

        // The picker offers "View" (not "Edit"); it opens the read-only detail.
        app.buttons["viewAppListButton-Distractions"].waitToAppear().tap()
        assertReadOnlyDetail(app)
    }

    func testAppListsEditableWithoutHardSession() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()
        app.element("selectedAppsRow").waitToAppear().tap()

        XCTAssertFalse(app.element("appListsLockedNotice").exists)
        // With no hard block, "Edit" (not "View") opens the full editor.
        XCTAssertFalse(app.buttons["viewAppListButton-Distractions"].exists)
        app.buttons["editAppListButton-Distractions"].waitToAppear().tap()
        app.element("appListNameField").waitToAppear()
        app.buttons["editAppsButton"].waitToAppear()
    }

    func testManageAppListsOpensEditorWhenUnlocked() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToSettingsTab()
        app.buttons["manageAppListsButton"].waitToAppear().tap()

        // No hard block: a management row taps straight into the full editor,
        // not the read-only detail.
        XCTAssertFalse(app.element("appListsLockedNotice").exists)
        app.element("appListRow-Distractions").waitToAppear().tap()

        app.element("appListNameField").waitToAppear()
        app.buttons["editAppsButton"].waitToAppear()
        XCTAssertFalse(
            app.element("appListReadOnlyNotice").exists,
            "An unlocked list opens the editor, not the read-only detail"
        )
    }

    /// Asserts the read-only `AppListDetailView` is showing: its lock notice is
    /// present and neither edit affordance (the apps picker, the Save button)
    /// exists — the "no editing" rule holds while a list is merely viewable.
    private func assertReadOnlyDetail(_ app: XCUIApplication) {
        app.element("appListReadOnlyNotice").waitToAppear()
        XCTAssertFalse(
            app.buttons["editAppsButton"].exists,
            "The app selection must stay locked in Hard Mode"
        )
        XCTAssertFalse(
            app.buttons["saveAppListButton"].exists,
            "Saving list changes must stay locked in Hard Mode"
        )
    }
}
