//
//  RuleCreationUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class RuleCreationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateScheduleRuleFromTypeCard() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.element("emptyRulesCard").waitToAppear()

        app.buttons["newRuleButton"].tap()
        app.staticTexts["New Rule"].waitToAppear()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()

        // Editor opens with the schedule defaults.
        XCTAssertEqual(app.staticTexts["ruleEditorTitle"].waitToAppear().label, "In the Zone")
        XCTAssertTrue(app.staticTexts["During this time"].exists)

        // The confirmation checkmark lives in the top chrome of the editor.
        // Under iOS 27 the sheet's chrome classifies that button inside the
        // sheet's Toolbar (not the NavigationBar) on the iPhone Duo, so match
        // by identifier anywhere — the identifier is unique to this control.
        let commit = app.buttons["commitRuleButton"].waitToAppear()
        XCTAssertEqual(commit.label, "Add Rule")
        commit.tap()
        app.buttons["ruleCard-In the Zone"].waitToAppear()
        XCTAssertFalse(app.element("emptyRulesCard").exists)
    }

    func testCreateRuleFromPreset() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()

        app.buttons["preset-morning-focus"].waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["ruleEditorTitle"].waitToAppear().label, "Morning Focus")

        app.buttons["commitRuleButton"].waitToAppear().tap()
        app.buttons["ruleCard-Morning Focus"].waitToAppear()
    }

    func testRenameRuleInEditor() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()

        // The rule name is an inline text field at the top of the editor —
        // no separate edit/rename button.
        XCTAssertFalse(app.buttons["renameButton"].exists)
        let nameField = app.textFields["ruleNameField"].waitToAppear()
        // Clear the field and type the new name, verifying the field actually
        // holds it — typeText drops keystrokes on a loaded CI runner, so a raw
        // type-then-assert flakes on the truncated value.
        nameField.setTextVerified("My Focus")

        // The title mirrors the typed name via a SwiftUI re-render, which lags
        // typeText on a slow runner — wait for it rather than reading it raw.
        app.staticTexts["ruleEditorTitle"].waitForLabel("My Focus")
        app.buttons["commitRuleButton"].waitToAppear().tap()
        app.buttons["ruleCard-My Focus"].waitToAppear()
    }

    func testDayTogglesFillRowAndHaveLargeTapTargets() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()

        let first = app.buttons["dayToggle-1"].waitToAppear()
        let last = app.buttons["dayToggle-7"].waitToAppear()
        XCTAssertGreaterThanOrEqual(
            first.frame.height, 44,
            "Day toggle tap target should be at least 44pt tall"
        )
        // Measured against the strip's own container row, not the window: narrow
        // phones span the editor sheet across the window, but iOS 27 presents the
        // sheet narrower on other form factors (e.g. the iPhone Duo), and the
        // invariant under test — "equal share, all seven in one row" — is
        // window-independent (DayOfWeekPicker's doc comment).
        let picker = app.element("dayOfWeekPicker").waitToAppear()
        let span = last.frame.maxX - first.frame.minX
        XCTAssertGreaterThan(
            span, picker.frame.width * 0.9,
            "Day toggles should share the picker row evenly, got \(span) of \(picker.frame.width)"
        )
        XCTAssertEqual(
            last.frame.minY, first.frame.minY,
            "All seven day toggles must sit in one row"
        )
    }

    func testCreateTimeLimitRule() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-timeLimit"].waitToAppear().tap()

        XCTAssertEqual(app.staticTexts["ruleEditorTitle"].waitToAppear().label, "Time Keeper")
        XCTAssertTrue(app.staticTexts["When I use"].exists)
        XCTAssertEqual(app.staticTexts["dailyLimitStepperValue"].label, "45m")
        // The stepper exposes a spoken value so VoiceOver announces changes.
        XCTAssertEqual(
            app.steppers["dailyLimitStepper"].value as? String, "45 minutes",
            "The daily-limit stepper must expose a spoken accessibility value"
        )

        // The stepper's labeled control suffixes its increment button id.
        app.steppers["dailyLimitStepper"].buttons["dailyLimitStepper-Increment"].tap()
        XCTAssertEqual(app.staticTexts["dailyLimitStepperValue"].label, "60m")
        XCTAssertEqual(app.steppers["dailyLimitStepper"].value as? String, "60 minutes")

        app.buttons["commitRuleButton"].waitToAppear().tap()
        app.buttons["ruleCard-Time Keeper"].waitToAppear()
    }

    func testEditorSupportsNativeSwipeBack() throws {
        // The edge-swipe starts at the window's left edge, which only lands on
        // the editor when the sheet spans the full width (compact width). In
        // regular width (iPad, open iPhone Duo) the editor is a centered form
        // sheet, so the equivalent back navigation is covered by
        // AppListUITests.testLimitEditorsAreBlockOnly (nav back button) instead.
        // The gate is the chrome the shell actually presents — the app must be
        // launched before asking — because iPad and an open iPhone Duo share the
        // same regular-width presentation while reporting different idioms.
        let app = XCUIApplication.launchOpenAppLock()
        try XCTSkipUnless(
            app.usesTabBarNavigation(),
            "Edge-swipe-back is a compact-width full-width-sheet gesture; regular-width back nav is covered elsewhere"
        )

        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()
        app.staticTexts["ruleEditorTitle"].waitToAppear()

        // Native push navigation supports the edge-swipe back gesture.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: middle)

        app.buttons["ruleKind-schedule"].waitToAppear()
        XCTAssertTrue(app.staticTexts["New Rule"].exists)
    }

    func testNewRuleSheetShowsTypesAndPresets() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()

        app.buttons["ruleKind-schedule"].waitToAppear()
        XCTAssertTrue(app.buttons["ruleKind-timeLimit"].exists)
        XCTAssertTrue(app.buttons["ruleKind-openLimit"].exists)
        XCTAssertTrue(app.staticTexts["Focus Time"].exists)
        XCTAssertTrue(app.buttons["preset-morning-focus"].exists)
        XCTAssertTrue(app.buttons["preset-deep-work"].exists)
    }

    func testCreateScheduleRuleAlertsIfStartEndTimesTooClose() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()
        app.staticTexts["ruleEditorTitle"].waitToAppear()

        let fromTimePicker = app.datePickers["fromTimePicker"]
        fromTimePicker.tap()
        app.set24hTimeOnTimePicker(hour: 9, minute: 0)
        app.staticTexts["ruleEditorTitle"].tapAtNormalizedOffset(0.5, 0.5)

        let toTimePicker = app.datePickers["toTimePicker"]
        toTimePicker.tap()
        app.set24hTimeOnTimePicker(hour: 9, minute: 5)
        app.staticTexts["ruleEditorTitle"].tapAtNormalizedOffset(0.5, 0.5)

        app.buttons["commitRuleButton"].waitToAppear().tap()

        XCTAssertTrue(app.staticTexts["Unable to save"].waitToAppear().exists)
    }

    func testCreateScheduleRuleAlertsIfStartTimeTooCloseToMidnight() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()
        app.staticTexts["ruleEditorTitle"].waitToAppear()

        let fromTimePicker = app.datePickers["fromTimePicker"]
        fromTimePicker.tap()
        app.set24hTimeOnTimePicker(hour: 23, minute: 50)
        app.staticTexts["ruleEditorTitle"].tapAtNormalizedOffset(0.5, 0.5)

        let toTimePicker = app.datePickers["toTimePicker"]
        toTimePicker.tap()
        app.set24hTimeOnTimePicker(hour: 9, minute: 0)
        app.staticTexts["ruleEditorTitle"].tapAtNormalizedOffset(0.5, 0.5)

        app.buttons["commitRuleButton"].waitToAppear().tap()

        XCTAssertTrue(app.staticTexts["Unable to save"].waitToAppear().exists)
    }
    
}
