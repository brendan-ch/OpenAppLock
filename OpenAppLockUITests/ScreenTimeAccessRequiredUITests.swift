//
//  ScreenTimeAccessRequiredUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class ScreenTimeAccessRequiredUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRevokedAuthorizationShowsAccessRequiredScreen() throws {
        let app = XCUIApplication.launchOpenAppLock(
            onboardingCompleted: true, screenTimeAccessRevoked: true
        )

        app.element("screenTimeAccessRequiredTitle").waitToAppear()
        XCTAssertTrue(app.buttons["screenTimeAccessOpenSettingsButton"].exists)
        XCTAssertFalse(app.buttons["newRuleButton"].exists)
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
    }

    func testApprovedAuthorizationShowsMainApp() throws {
        let app = XCUIApplication.launchOpenAppLock(onboardingCompleted: true)

        app.waitForMainUI()
        XCTAssertFalse(app.buttons["screenTimeAccessOpenSettingsButton"].exists)
    }
}
