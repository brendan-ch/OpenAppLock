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

        // Permission step: granting (mocked) lands on the main app, in whichever
        // navigation chrome the device uses (tab bar on iPhone, sidebar on iPad).
        app.buttons["allowScreenTimeButton"].waitToAppear().tap()
        app.waitForMainUI()
        XCTAssertTrue(app.staticTexts["Currently Blocking"].waitToAppear().exists)
    }

    func testCompletedOnboardingIsSkipped() throws {
        let app = XCUIApplication.launchOpenAppLock(onboardingCompleted: true)
        app.waitForMainUI()
        XCTAssertFalse(app.buttons["onboardingContinueButton"].exists)
    }
}
