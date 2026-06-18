//
//  NavigationChromeUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The post-onboarding shell adapts its navigation chrome to the available width:
/// a bottom tab bar on iPhone (compact), a left sidebar on full-screen iPad
/// (regular). These flows run on whatever destination the suite is launched
/// against and branch on the device idiom, so the same test validates both legs
/// of the CI matrix.
final class NavigationChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// iPad shows a sidebar and no tab bar; iPhone shows a tab bar and no sidebar.
    func testNavigationChromeMatchesIdiom() throws {
        let app = XCUIApplication.launchOpenAppLock()

        if UIDevice.current.userInterfaceIdiom == .pad {
            app.element("sidebarItem-home").waitToAppear()
            app.element("sidebarItem-rules").waitToAppear()
            app.element("sidebarItem-settings").waitToAppear()
            XCTAssertFalse(
                app.tabBars.firstMatch.exists,
                "Full-screen iPad should use a sidebar, not a bottom tab bar"
            )
        } else {
            app.tabBars.buttons["Home"].waitToAppear()
            XCTAssertFalse(
                app.element("sidebarItem-home").exists,
                "iPhone should use a bottom tab bar, not a sidebar"
            )
        }
    }

    /// Every section is reachable through whichever chrome is presented, proving
    /// the shared `goTo…` helpers drive both the tab bar and the sidebar.
    func testEverySectionIsReachable() throws {
        let app = XCUIApplication.launchOpenAppLock()

        app.goToRulesTab()
        app.element("newRuleButton").waitToAppear()

        app.goToSettingsTab()
        app.switches["uninstallProtectionToggle"].waitToAppear()

        app.goToHomeTab()
        app.element("nothingBlockedLabel").waitToAppear()
    }
}
