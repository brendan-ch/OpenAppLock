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

        // The confirmation checkmark lives in the navigation bar and carries
        // a descriptive accessibility label.
        let commit = app.navigationBars.buttons["commitRuleButton"].waitToAppear()
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
        // Tap at the trailing edge so the cursor lands after the last character.
        nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let deletions = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 24)
        nameField.typeText(deletions + "My Focus\n")

        XCTAssertEqual(app.staticTexts["ruleEditorTitle"].label, "My Focus")
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
        // The "fill the row" guarantee is measured against the window width, which
        // only holds where the editor sheet spans the full width (iPhone). On iPad
        // the editor is a centered form sheet narrower than the window, so that
        // comparison doesn't apply; the toggles still fill their (narrower) row.
        if UIDevice.current.userInterfaceIdiom == .phone {
            let span = last.frame.maxX - first.frame.minX
            XCTAssertGreaterThan(
                span, app.frame.width * 0.75,
                "Day toggles should span the full row width, got \(span) of \(app.frame.width)"
            )
        }
    }

    func testDayTogglesUpdateSummary() throws {
        let app = XCUIApplication.launchOpenAppLock()
        app.goToRulesTab()
        app.buttons["newRuleButton"].waitToAppear().tap()
        app.buttons["ruleKind-schedule"].waitToAppear().tap()

        // Default is Weekdays; enabling Saturday and Sunday makes it Every day.
        XCTAssertTrue(app.staticTexts["Weekdays"].waitToAppear().exists)
        app.buttons["dayToggle-1"].tap()
        app.buttons["dayToggle-7"].tap()
        XCTAssertTrue(app.staticTexts["Every day"].waitToAppear().exists)
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
        // The edge-swipe starts at the window's left edge, which only lands on the
        // editor when the sheet spans the full width (iPhone). On iPad the editor
        // is a centered form sheet, so the equivalent back navigation is covered by
        // AppListUITests.testLimitEditorsAreBlockOnly (nav back button) instead.
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Edge-swipe-back is an iPhone full-width-sheet gesture; iPad back nav is covered elsewhere"
        )

        let app = XCUIApplication.launchOpenAppLock()
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
}
