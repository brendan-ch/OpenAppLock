//
//  UITestSupport.swift
//  OpenAppLockUITests
//

import XCTest

extension XCUIApplication {
    /// Launches the app in UI-testing mode: in-memory storage, mocked Screen
    /// Time authorization, and no shield side effects.
    ///
    /// `gitHubURL` / `websiteURL` override the configured Settings links with
    /// deterministic values, so link tests don't depend on the committed build
    /// settings (which point at the real, swappable destinations).
    static func launchOpenAppLock(
        onboardingCompleted: Bool = true,
        seedScenario: String? = nil,
        gitHubURL: String? = nil,
        websiteURL: String? = nil,
        notificationsAuthorized: Bool = false,
        screenTimeAccessRevoked: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ui-testing"]
        arguments.append(onboardingCompleted ? "-onboarding-completed" : "-onboarding-required")
        if let seedScenario {
            arguments.append("-seed-scenario=\(seedScenario)")
        }
        if let gitHubURL {
            arguments.append("-github-url=\(gitHubURL)")
        }
        if let websiteURL {
            arguments.append("-website-url=\(websiteURL)")
        }
        if notificationsAuthorized {
            arguments.append("-notifications-authorized")
        }
        if screenTimeAccessRevoked {
            arguments.append("-screen-time-access-revoked")
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }
}

extension XCUIApplication {
    /// Finds an element by accessibility identifier regardless of how SwiftUI
    /// exposes it (Other, StaticText, Button, …).
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}

extension XCUIApplication {
    /// Switches to the Home section (Currently Blocking + Usage). Home is the
    /// default selection, so most Home tests don't need to call this.
    func goToHomeTab() { goToSection(tabLabel: "Home", sidebarIdentifier: "sidebarItem-home") }
    /// Switches to the Rules section (the rule list + New Rule button).
    func goToRulesTab() { goToSection(tabLabel: "Rules", sidebarIdentifier: "sidebarItem-rules") }
    /// Switches to the Settings section (Uninstall Protection + Manage App Lists).
    func goToSettingsTab() { goToSection(tabLabel: "Settings", sidebarIdentifier: "sidebarItem-settings") }

    /// Navigates to a top-level section regardless of the current navigation
    /// chrome: the bottom tab bar in compact width (iPhone, iPhone Duo closed —
    /// rendered by iOS 27 as a vertical trailing rail), or the left sidebar in
    /// regular width (full-screen iPad, open iPhone Duo). Keeps the rest of the
    /// UI suite agnostic to which device it runs on.
    ///
    /// Each section's detail names its navigation bar after the same label as the
    /// tab/row (`navigationTitle("Rules")` → `navigationBars["Rules"]`), giving a
    /// device-agnostic "we actually landed" post-condition.
    private func goToSection(
        tabLabel: String, sidebarIdentifier: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let tab = tabBars.buttons[tabLabel].firstMatch
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
            return
        }

        // iPhone Duo's iOS 27 vertical rail (see `usesTabBarNavigation`).
        let rail = railTabButton(tabLabel)
        if rail.waitForExistence(timeout: 2) {
            rail.tap()
            return
        }

        // iPad sidebar (NavigationSplitView). A single synthesized tap on a
        // selection-driven sidebar row is occasionally dropped before the app has
        // quiesced — the row never becomes selected and the detail stays on the
        // previous section, so a following content assertion flakes. Confirm the
        // target section's detail actually appeared and re-tap if it didn't,
        // rather than assuming the first tap took.
        let item = element(sidebarIdentifier).waitToAppear(file: file, line: line)
        let sectionBar = navigationBars[tabLabel]
        for _ in 0..<5 {
            item.tap()
            if sectionBar.waitForExistence(timeout: 2) { return }
        }
        XCTAssertTrue(
            sectionBar.exists,
            "Sidebar navigation to \(tabLabel) never landed after repeated taps",
            file: file, line: line
        )
    }

    /// Waits for the post-onboarding shell to appear in whichever chrome the
    /// (possibly foldable) device presents — a tab bar (classic horizontal, or
    /// iPhone Duo's vertical rail) in compact width, the left sidebar in regular
    /// width (full-screen iPad, open iPhone Duo) — so tests can confirm "we
    /// reached the main app" without hard-coding one device's navigation.
    @discardableResult
    func waitForMainUI() -> XCUIApplication {
        if usesTabBarNavigation() {
            // The two tab renderings are mutually exclusive, so whichever query
            // comes up empty below is guaranteed to stay empty; on the rail the
            // classic `tabBars` query never matches (and vice versa).
            let classic = tabBars.buttons["Home"].firstMatch
            (classic.waitForExistence(timeout: 3) ? classic : railTabButton("Home")).waitToAppear()
        } else {
            element("sidebarItem-home").waitToAppear()
        }
        return self
    }

    /// The tab control for `label` as iPhone Duo's iOS 27 vertical trailing
    /// rail: plain buttons inside a `Toolbar`, which XCUITest doesn't classify
    /// as a `TabBar`. Empty on every other device/pose.
    func railTabButton(_ label: String) -> XCUIElement {
        toolbars.buttons[label].firstMatch
    }

    /// Whether the post-onboarding shell is currently presenting tab-style
    /// navigation (compact width), decided by sniffing the tree rather than the
    /// device idiom: iPhone Duo identifies as `.phone` in both poses, but shows
    /// the regular-width sidebar (like a full-screen iPad) while open, and its
    /// compact tab bar is a vertical rail that `tabBars` doesn't match — so
    /// neither `userInterfaceIdiom` nor `tabBars` alone predicts the chrome.
    func usesTabBarNavigation(timeout: TimeInterval = 5) -> Bool {
        if tabBars.firstMatch.waitForExistence(timeout: timeout) { return true }
        return railTabButton("Home").waitForExistence(timeout: 1)
    }

    /// The first hittable element matching `query` that exists, waiting for the
    /// query to resolve first. iOS 27 keeps the occluded nav stacks of windows
    /// behind a presented sheet alive in the hierarchy, so the same identifier
    /// can match controls in both the visible sheet and the background window —
    /// only the visible one is hittable.
    func hittableElement(
        _ query: XCUIElementQuery, identifier: String,
        timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let matched = query.matching(identifier: identifier)
        matched.firstMatch.waitToAppear(timeout: timeout, file: file, line: line)
        if let hit = matched.allElementsBoundByIndex.first(where: { $0.isHittable }) {
            return hit
        }
        return matched.firstMatch
    }
}

extension XCUIApplication {
    /// Given a 24-hour time, adjust the hour/minute wheels of the open time picker. Works against pickers in the 12h and 24h formats, but may not work against other formats.
    func set24hTimeOnTimePicker(hour: Int, minute: Int) {
        let wheels = self.pickerWheels
        if wheels.count >= 3 {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: "\(hour % 12 == 0 ? 12 : hour % 12)")
            wheels.element(boundBy: 2).adjust(toPickerWheelValue: hour >= 12 ? "PM" : "AM")
        } else {
            wheels.element(boundBy: 0).adjust(toPickerWheelValue: String(format: "%02d", hour))
        }
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: String(format: "%02d", minute))

    }
}

extension XCUIElement {
    /// Taps a point inside this element's own frame at normalized offsets,
    /// rather than a coordinate derived from the whole app window.
    func tapAtNormalizedOffset(_ dx: CGFloat, _ dy: CGFloat) {
        coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
    }

    /// Asserts the element appears within the timeout, then returns it. The
    /// default is generous (15s) because the CI runners are frequently
    /// overloaded — sheet/picker presentations and SwiftData-backed renders can
    /// take well over 5s there, which flaked positive "wait for it" assertions
    /// across the UI suite. A wrong/absent element still fails, just later.
    @discardableResult
    func waitToAppear(
        timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            waitForExistence(timeout: timeout),
            "Expected \(self) to exist within \(timeout)s",
            file: file, line: line
        )
        return self
    }

    /// Polls until the element's `label` equals `expected`, then returns it.
    /// Use instead of reading `.label` straight after an action that updates it
    /// asynchronously (e.g. a SwiftUI re-render after `typeText`): on a slow CI
    /// runner the label lags the action, and a bare `XCTAssertEqual` races it.
    @discardableResult
    func waitForLabel(
        _ expected: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected), object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "Expected label \"\(expected)\" within \(timeout)s, got \"\(label)\"",
            file: file, line: line)
        return self
    }

    /// Polls until the element's `label` contains `substring`, then returns it.
    /// The `contains` counterpart to `waitForLabel(_:)`, for labels that embed
    /// dynamic text around the part under test (e.g. a combined detail row,
    /// "Status, Resumes in 15m", whose countdown varies) and update
    /// asynchronously after an action — a bare `.label.contains` read races the
    /// SwiftUI re-render on a slow runner.
    @discardableResult
    func waitForLabel(
        containing substring: String, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", substring), object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(
            result, .completed,
            "Expected label to contain \"\(substring)\" within \(timeout)s, got \"\(label)\"",
            file: file, line: line)
        return self
    }

    /// Taps the element, then confirms `result` actually appeared, re-tapping if it
    /// didn't — a single synthesized tap on a SwiftUI navigation row/button is
    /// occasionally dropped on a loaded CI runner before the app has quiesced
    /// (same failure mode `goToSection` works around for sidebar rows). Skips the
    /// re-tap when this element has already left the hierarchy (the tap landed,
    /// the destination is just slow to appear).
    @discardableResult
    func tap(
        untilAppears result: XCUIElement, attempts: Int = 4, timeout: TimeInterval = 4,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        for _ in 0..<attempts {
            if exists && isHittable { tap() }
            if result.waitForExistence(timeout: timeout) { return result }
        }
        XCTFail(
            "Tapping \(self) never made \(result) appear after \(attempts) attempts",
            file: file, line: line)
        return result
    }

    /// Replaces the field's text with `text` and verifies the field actually holds
    /// it, retrying from scratch on mismatch — `typeText` drops keystrokes on a
    /// loaded CI runner (observed truncations like "My Foc" for "My Focus"), so
    /// typing without verification flakes any later assertion on the typed value.
    /// Submits with a trailing newline only after the value verifies.
    ///
    /// Caveat: SwiftUI TextFields with placeholder text report the placeholder
    /// from `value` when empty, which inflates the delete count harmlessly.
    func setTextVerified(
        _ text: String, attempts: Int = 3,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        var lastObserved = ""
        for _ in 0..<attempts {
            coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            let existing = (value as? String) ?? ""
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 4))
            typeText(text)

            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", text), object: self)
            if XCTWaiter().wait(for: [expectation], timeout: 3) == .completed {
                typeText("\n")
                return
            }
            lastObserved = (value as? String) ?? ""
        }
        XCTFail(
            "Field never held \"\(text)\" after \(attempts) attempts; last value \"\(lastObserved)\"",
            file: file, line: line)
    }
}
