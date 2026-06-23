//
//  NotificationSettingsUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The Settings → Notifications sub-page: granting permission enables the two
/// opt-in type toggles, which then flip and persist.
final class NotificationSettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Coordinate tap — `.tap()` lands on the row label and doesn't reliably flip
    /// a SwiftUI switch.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func openNotificationSettings(_ app: XCUIApplication) {
        app.goToSettingsTab()
        app.element("notificationSettingsButton").waitToAppear().tap()
    }

    func testGrantingPermissionEnablesAndFlipsToggles() throws {
        // Launch undetermined: the grant transition is the path under test.
        let app = XCUIApplication.launchOpenAppLock()
        openNotificationSettings(app)

        // Before granting: the Allow button shows and the toggles are disabled.
        let allow = app.element("allowNotificationsButton").waitToAppear()
        let scheduleToggle = app.switches["scheduleStartNotificationToggle"].waitToAppear()
        let limitToggle = app.switches["timeLimitNotificationToggle"].waitToAppear()
        XCTAssertFalse(scheduleToggle.isEnabled, "Toggle should be disabled until granted")
        XCTAssertFalse(limitToggle.isEnabled, "Toggle should be disabled until granted")

        allow.tap()

        // After granting: the status row appears and the toggles enable.
        app.element("notificationStatusLabel").waitToAppear()
        expectation(
            for: NSPredicate(format: "isEnabled == true"), evaluatedWith: scheduleToggle)
        waitForExpectations(timeout: 3)

        XCTAssertEqual(scheduleToggle.value as? String, "0")
        flip(scheduleToggle)
        XCTAssertEqual(scheduleToggle.value as? String, "1", "Granting should let the toggle flip")
    }

    func testTogglesFlipWhenAlreadyAuthorized() throws {
        let app = XCUIApplication.launchOpenAppLock(notificationsAuthorized: true)
        openNotificationSettings(app)

        app.element("notificationStatusLabel").waitToAppear()
        let scheduleToggle = app.switches["scheduleStartNotificationToggle"].waitToAppear()
        let limitToggle = app.switches["timeLimitNotificationToggle"].waitToAppear()

        // Existence isn't interactivity: on a loaded runner a switch can be on
        // screen but not yet hit-testable, so the coordinate tap lands before it
        // is live and gets dropped (leaving the value at "0"). Wait for the
        // authorized state to enable both toggles before flipping — same barrier
        // `testGrantingPermissionEnablesAndFlipsToggles` uses after granting.
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: scheduleToggle)
        expectation(for: enabled, evaluatedWith: limitToggle)
        waitForExpectations(timeout: 3)

        XCTAssertEqual(scheduleToggle.value as? String, "0", "Type toggles default off")
        XCTAssertEqual(limitToggle.value as? String, "0", "Type toggles default off")

        flip(scheduleToggle)
        XCTAssertEqual(scheduleToggle.value as? String, "1")
        flip(limitToggle)
        XCTAssertEqual(limitToggle.value as? String, "1")
    }
}
