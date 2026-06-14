//
//  OnboardingUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingWalksThroughPermissionToHome() throws {
        let app = XCUIApplication.launchOpenAppLock(onboardingCompleted: false)

        // Welcome step.
        app.staticTexts["OpenAppLock"].waitToAppear()
        app.buttons["onboardingContinueButton"].waitToAppear().tap()

        // Permission step: granting (mocked) lands on the tabbed home screen.
        app.buttons["allowScreenTimeButton"].waitToAppear().tap()
        app.tabBars.buttons["Home"].waitToAppear()
        XCTAssertTrue(app.tabBars.buttons["Rules"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertTrue(app.staticTexts["Currently Blocking"].exists)
    }

    func testCompletedOnboardingIsSkipped() throws {
        let app = XCUIApplication.launchOpenAppLock(onboardingCompleted: true)
        app.tabBars.buttons["Home"].waitToAppear()
        XCTAssertFalse(app.buttons["onboardingContinueButton"].exists)
    }
}
