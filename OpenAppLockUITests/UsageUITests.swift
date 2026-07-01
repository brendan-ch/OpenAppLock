//
//  UsageUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The "Active Rules" section on Home — seeded limit rules show their daily
/// budget (no live count), a spent rule moves to Currently Blocking reading
/// "Blocked until tomorrow", and rows open the rule-detail overlay.
final class UsageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testActiveRulesShowBudgets() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        XCTAssertTrue(app.staticTexts["Active Rules"].waitToAppear().exists)

        let timeRow = app.element("activeRuleRow-Time Keeper").waitToAppear()
        XCTAssertTrue(timeRow.label.contains("Time Limit"), "Got: \(timeRow.label)")
        XCTAssertTrue(timeRow.label.contains("45m / day"), "Got: \(timeRow.label)")

        let openRow = app.element("activeRuleRow-Gate Keeper").waitToAppear()
        XCTAssertTrue(openRow.label.contains("Open Limit"), "Got: \(openRow.label)")
        XCTAssertTrue(openRow.label.contains("5 opens / day"), "Got: \(openRow.label)")
    }

    func testSpentBudgetMovesToCurrentlyBlocking() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        // A spent budget is a real block: the rule moves out of Active Rules and
        // into Currently Blocking, reading "Blocked until tomorrow".
        let tile = app.buttons["blockedTile-Doom Scroll"].waitToAppear()
        XCTAssertTrue(tile.label.contains("Blocked until tomorrow"), "Got: \(tile.label)")

        XCTAssertFalse(
            app.element("activeRuleRow-Doom Scroll").exists,
            "A spent rule should leave Active Rules for Currently Blocking")
    }

    func testSpentBudgetRowOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        // A spent budget's Currently Blocking row opens the detail overlay.
        app.buttons["blockedTile-Doom Scroll"].waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Doom Scroll")
    }

    func testTappingActiveRuleOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        app.element("activeRuleRow-Time Keeper").waitToAppear().tap()
        let name = app.staticTexts["detailRuleName"].waitToAppear()
        XCTAssertEqual(name.label, "Time Keeper")

        // Time limit rules' General section shows Kind but omits Status — the
        // budget it would repeat is already covered by the Details rows below.
        let kind = app.element("detailRow-Kind").waitToAppear()
        XCTAssertTrue(kind.label.contains("Time Limit"), "Got: \(kind.label)")
        XCTAssertFalse(
            app.element("detailRow-Status").exists,
            "Time limit rules should not show a Status row in General"
        )
    }

    func testOpenLimitRuleDetailStillShowsStatusRow() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        app.element("activeRuleRow-Gate Keeper").waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Gate Keeper")

        // Unlike time limit, open limit rules keep the Status row — only
        // .timeLimit is special-cased out of General.
        let kind = app.element("detailRow-Kind").waitToAppear()
        XCTAssertTrue(kind.label.contains("Open Limit"), "Got: \(kind.label)")
        XCTAssertTrue(
            app.element("detailRow-Status").exists,
            "Open limit rules should still show a Status row in General"
        )
    }
}
