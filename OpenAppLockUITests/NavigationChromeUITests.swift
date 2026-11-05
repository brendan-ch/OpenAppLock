//
//  NavigationChromeUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The post-onboarding shell adapts its navigation chrome to the available
/// width: a bottom tab bar in compact width, a left sidebar in regular width
/// (full-screen iPad, open iPhone Duo). These flows run on whatever destination
/// the suite is launched against and detect the chrome from the tree itself —
/// not the device idiom, because an open iPhone Duo presents regular-width
/// chrome and iPhone idiom in the same pose — so the same test validates every
/// leg of the CI matrix.
final class NavigationChromeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Compact width shows a tab bar and no sidebar; regular width shows the
    /// sidebar and no tab bar.
    func testNavigationChromeMatchesAvailableWidth() throws {
        let app = XCUIApplication.launchOpenAppLock()

        if app.usesTabBarNavigation() {
            // Either tab rendering satisfies "compact width chrome"; the two
            // forms are mutually exclusive (see `waitForMainUI`).
            let classic = app.tabBars.buttons["Home"].firstMatch
            (classic.waitForExistence(timeout: 3) ? classic : app.railTabButton("Home")).waitToAppear()
            XCTAssertFalse(
                app.element("sidebarItem-home").exists,
                "Compact width should use tab navigation, not a sidebar"
            )
        } else {
            app.element("sidebarItem-home").waitToAppear()
            app.element("sidebarItem-rules").waitToAppear()
            app.element("sidebarItem-settings").waitToAppear()
            XCTAssertFalse(
                app.tabBars.firstMatch.exists,
                "Regular width should use a sidebar, not a bottom tab bar"
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
