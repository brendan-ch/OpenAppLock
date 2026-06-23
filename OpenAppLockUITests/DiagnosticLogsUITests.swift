//
//  DiagnosticLogsUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// Settings → Diagnostics → Logs export flow. Launches with `-seed-logs`, which
/// writes deterministic `SEED-MARKER` entries into the per-launch temp log dir,
/// then asserts the day appears, its detail shows the seeded content and an
/// export control, and Clear empties the list. The system share sheet is
/// out-of-process, so the export control is asserted as present/tappable but its
/// sheet contents are not.
final class DiagnosticLogsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Today's local day key, matching `UsageLedger.dayKey` / the file bucket.
    private var todayKey: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func testSeededLogsExportAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding-completed", "-seed-logs"]
        app.launch()

        app.goToSettingsTab()

        // Settings → Diagnostics → Logs
        let logsRow = app.element("diagnosticsLogsRow")
        XCTAssertTrue(logsRow.waitForExistence(timeout: 5))
        logsRow.tap()

        // Today's seeded day row is present; open it.
        let dayRow = app.element("logDayRow-\(todayKey)")
        XCTAssertTrue(dayRow.waitForExistence(timeout: 5), "expected a log day row for today")
        dayRow.tap()

        // The merged day text contains a seeded marker and the export control exists.
        let dayText = app.element("logDayText")
        XCTAssertTrue(dayText.waitForExistence(timeout: 5))
        XCTAssertTrue(
            dayText.label.contains("SEED-MARKER"), "seeded entries should appear in the day log")
        XCTAssertTrue(app.element("exportLogButton").waitForExistence(timeout: 5))

        // Back to the days list, clear, confirm, and expect the empty state.
        app.navigationBars[todayKey].buttons.firstMatch.tap()  // back to "Logs"
        let clear = app.element("clearLogsButton")
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        // Confirmation dialog's destructive action (sheet button).
        app.sheets.buttons["Clear All Logs"].tap()

        XCTAssertTrue(
            app.element("noLogsLabel").waitForExistence(timeout: 5),
            "after clearing, the empty state should show")
    }
}
