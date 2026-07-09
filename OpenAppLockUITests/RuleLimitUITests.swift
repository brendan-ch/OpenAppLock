//
//  RuleLimitUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class RuleLimitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAlertShownWhenAtRuleCap() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "at-rule-cap")
        app.goToRulesTab()

        app.buttons["newRuleButton"].waitToAppear().tap()

        // The cap alert appears and the New Rule sheet does not.
        app.alerts["Rule limit reached"].waitToAppear()
        XCTAssertFalse(app.staticTexts["New Rule"].exists)
        app.alerts.buttons["OK"].tap()
    }

    func testNoAlertBelowRuleCap() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["newRuleButton"].waitToAppear().tap()

        // Below the cap the New Rule sheet opens and no alert shows.
        app.staticTexts["New Rule"].waitToAppear()
        XCTAssertFalse(app.alerts["Rule limit reached"].exists)
    }
}
