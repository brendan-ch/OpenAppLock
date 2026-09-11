//
//  DeepLinkTests.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import XCTest

final class DeepLinkUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    func testOpenLinkOpensRuleIfAppOpenOnHomeView() {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        
        let ruleIDLabel = app.staticTexts["ruleIDLabel"].label
        let uuidString = ruleIDLabel.split(separator: ":").map(String.init).last?.trimmingCharacters(in: .whitespaces)
        guard let uuidString = uuidString else {
            XCTFail("Unable to obtain rule UUID")
            return
        }
        
        app.buttons["closeDetailButton"].tap()
        app.goToHomeTab()
        
        let springboardApp = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboardApp.activate()
        
        guard let url = URL(string: "openapplock://rules/\(uuidString)") else {
            XCTFail("Unable to construct URL")
            return
        }
        XCUIDevice.shared.system.open(url)
        
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Sleep")
        app.buttons["closeDetailButton"].tap()
        XCTAssertTrue(app.staticTexts["Home"].waitToAppear().exists)
    }
    
    
    func testOpenLinkOpensRuleIfAppOpenOnRulesView() {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        
        app.buttons["ruleCard-Sleep"].waitToAppear().tap()
        
        let ruleIDLabel = app.staticTexts["ruleIDLabel"].label
        let uuidString = ruleIDLabel.split(separator: ":").map(String.init).last?.trimmingCharacters(in: .whitespaces)
        guard let uuidString = uuidString else {
            XCTFail("Unable to obtain rule UUID")
            return
        }
        
        app.buttons["closeDetailButton"].tap()
        
        let springboardApp = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboardApp.activate()
        
        guard let url = URL(string: "openapplock://rules/\(uuidString)") else {
            XCTFail("Unable to construct URL")
            return
        }
        XCUIDevice.shared.system.open(url)
        
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Sleep")
        app.buttons["closeDetailButton"].tap()
        XCTAssertTrue(app.staticTexts["Rules"].waitToAppear().exists)

    }
}
