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

        // The App List row pushes the selection screen onto the editor's stack.
        app.element("selectedAppsRow").waitToAppear().tap()

        // Fresh install: no lists yet, so the selection screen offers creation.
        app.element("emptyAppListsLabel").waitToAppear()
        app.buttons["newAppListButton"].tap()

        // The list editor pops out as its own sheet overlay.
        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Focus Apps\n")

        // Edit Apps pushes the Screen Time picker; selections apply live, so it
        // has no Save of its own — the nav back button returns to the editor.
        app.element("emptySelectionLabel").waitToAppear()
        app.buttons["editAppsButton"].tap()
        let appsBar = app.navigationBars["Edit Apps"].waitToAppear()
        appsBar.buttons["BackButton"].tap()

        // The editor's checkmark saves the list and dismisses the overlay.
        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Back on the selection screen with the new list present; tapping it
        // selects the list and pops back to the rule editor.
        app.element("appListRow-Focus Apps").waitToAppear().tap()

        // The editor row now reports the chosen list.
        let row = app.element("selectedAppsRow").waitToAppear()
        XCTAssertTrue(row.label.contains("Focus Apps"), "Got: \(row.label)")
    }

    func testClosingListEditorWithEditsPromptsToDiscard() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        app.buttons["editRuleButton"].waitToAppear().tap()

        // Open the "Distractions" list for editing (a sheet overlay).
        app.element("selectedAppsRow").waitToAppear().tap()
        app.buttons["editAppListButton-Distractions"].waitToAppear().tap()

        // Make an outstanding edit by renaming the list (submit to drop the
        // keyboard, which otherwise interferes with resolving the dialog).
        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText(" Edited\n")

        // Closing with unsaved edits raises the standard discard confirmation.
        app.buttons["closeAppListButton"].tap()
        XCTAssertTrue(
            app.buttons["Discard Changes"].waitToAppear().exists,
            "Closing with unsaved edits should confirm before discarding"
        )

        // Discarding dismisses the editor; the rename is dropped.
        app.buttons["Discard Changes"].tap()

        // Back on the selection screen with the original list name intact.
        app.element("appListRow-Distractions").waitToAppear()
        XCTAssertFalse(
            app.textFields["appListNameField"].exists,
            "Discarding should close the editor overlay"
        )
    }

    func testClosingUneditedListEditorDismissesWithoutPrompt() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToSettingsTab()
        app.element("manageAppListsButton").waitToAppear().tap()

        // Open the list and close it again without touching anything.
        app.element("appListRow-Distractions").waitToAppear().tap()
        app.textFields["appListNameField"].waitToAppear()
        app.buttons["closeAppListButton"].tap()

        // No outstanding edits, so it closes straight away — no discard prompt.
        XCTAssertFalse(
            app.buttons["Discard Changes"].waitForExistence(timeout: 1.5),
            "Closing an unedited list must not prompt to discard"
        )
        app.element("appListRow-Distractions").waitToAppear()
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

    func testAppListEditorMenuDeletesUnusedList() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToSettingsTab()
        app.buttons["manageAppListsButton"].waitToAppear().tap()

        // Create a fresh, unused list — "Distractions" is in use and can't go.
        app.buttons["newAppListButton"].waitToAppear().tap()
        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Scratch List\n")
        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Reopen it and delete via the new options menu (no swipe needed).
        app.element("appListRow-Scratch List").waitToAppear().tap()
        app.buttons["appListActionsMenu"].waitToAppear().tap()
        app.buttons["deleteAppListButton"].waitToAppear().tap()

        // Deleting an unused list confirms first, then removes it.
        app.sheets.buttons["Delete"].waitToAppear().tap()
        XCTAssertFalse(
            app.element("appListRow-Scratch List").waitForExistence(timeout: 2),
            "Confirming the menu delete should remove the unused list"
        )
    }

    func testAppListEditorMenuBlocksDeletingListInUse() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToSettingsTab()
        app.buttons["manageAppListsButton"].waitToAppear().tap()

        // "Distractions" is used by Work Time + Sleep, so the menu delete is barred.
        app.element("appListRow-Distractions").waitToAppear().tap()
        app.buttons["appListActionsMenu"].waitToAppear().tap()
        app.buttons["deleteAppListButton"].waitToAppear().tap()

        // The blocking alert appears in place of a delete confirmation.
        app.alerts["This list is in use"].waitToAppear()
        app.alerts.buttons["OK"].tap()

        // The editor is still open; the list survives.
        app.element("appListNameField").waitToAppear()
    }

    func testSwipeDeletingUnusedListConfirmsFirst() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToSettingsTab()
        app.buttons["manageAppListsButton"].waitToAppear().tap()

        app.buttons["newAppListButton"].waitToAppear().tap()
        let nameField = app.textFields["appListNameField"].waitToAppear()
        nameField.tap()
        nameField.typeText("Scratch List\n")
        app.buttons["saveAppListButton"].waitToAppear().tap()

        // Swipe-to-delete now confirms before removing the list.
        let row = app.element("appListRow-Scratch List").waitToAppear()
        row.swipeLeft()
        app.buttons["Delete"].waitToAppear().tap()
        app.sheets.buttons["Delete"].waitToAppear().tap()

        XCTAssertFalse(
            app.element("appListRow-Scratch List").waitForExistence(timeout: 2),
            "Confirming the swipe delete should remove the list"
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
