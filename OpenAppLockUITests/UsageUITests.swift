//
//  UsageUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The Usage section on the Home tab — seeded with limit rules at various
/// budget states ("Time Keeper" 18m/45m, "Gate Keeper" 2/5 opens,
/// "Doom Scroll" spent → moved to Currently Blocking).
final class UsageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUsageSectionShowsTypeAndBudgets() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        XCTAssertTrue(app.staticTexts["Usage"].waitToAppear().exists)

        // The row leads with the rule type, then the live usage of the budget.
        let timeRow = app.element("usageRow-Time Keeper").waitToAppear()
        XCTAssertTrue(timeRow.label.contains("Time Limit"), "Got: \(timeRow.label)")
        XCTAssertTrue(timeRow.label.contains("18m of 45m used"), "Got: \(timeRow.label)")

        let openRow = app.element("usageRow-Gate Keeper").waitToAppear()
        XCTAssertTrue(openRow.label.contains("Open Limit"), "Got: \(openRow.label)")
        XCTAssertTrue(openRow.label.contains("2 of 5 opens"), "Got: \(openRow.label)")
    }

    func testSpentBudgetMovesToCurrentlyBlocking() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        // A spent budget is a real block: the rule moves out of Usage and into
        // Currently Blocking, carrying its type + usage tracking.
        let tile = app.buttons["blockedTile-Doom Scroll"].waitToAppear()
        XCTAssertTrue(tile.label.contains("Time Limit"), "Got: \(tile.label)")
        XCTAssertTrue(tile.label.contains("30m of 30m used"), "Got: \(tile.label)")

        // It is no longer tracked under Usage.
        XCTAssertFalse(
            app.element("usageRow-Doom Scroll").exists,
            "A spent rule should leave the Usage section for Currently Blocking"
        )
    }

    func testSpentBudgetCanBeUnblockedUntilTomorrow() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        app.buttons["blockedTile-Doom Scroll"].waitToAppear().tap()
        app.sheets.buttons["Unblock"].waitToAppear().tap()

        // Unblocked → paused (not blocking), so it drops back into Usage.
        app.staticTexts["nothingBlockedLabel"].waitToAppear()
        let row = app.element("usageRow-Doom Scroll").waitToAppear()
        XCTAssertTrue(row.label.contains("Paused"), "Got: \(row.label)")
    }
}
