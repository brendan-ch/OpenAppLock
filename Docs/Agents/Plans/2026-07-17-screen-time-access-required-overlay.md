# Screen Time Access Required Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **The controlling session, not the implementer subagent, runs builds/tests via the Xcode MCP tools** (`BuildProject`, `RunSomeTests`, `RunAllTests`) between tasks — subagents cannot reach the Xcode MCP. Each task also gets an opus `code-reviewer` + `security-reviewer` pass (dispatched in parallel) before moving to the next task.

**Goal:** Show a full-screen block with a link to system Settings whenever Screen Time access was granted during onboarding but is later revoked, instead of the app silently doing nothing.

**Architecture:** Extend `RootView`'s existing two-way onboarding gate into a three-way `switch` over a new pure `RootDestination.resolve(hasCompletedOnboarding:authorizationStatus:)`, driven by `ScreenTimeAuthorization.status` (already refreshed on every foreground). Add a new `ScreenTimeAccessRequiredView` for the blocked state.

**Tech Stack:** SwiftUI, Swift Testing (`@Test`/`#expect`), XCUITest, existing `LaunchConfiguration`/`MockAuthorizationProvider` UI-test harness.

## Global Constraints

- Follow `AGENTS.md` "Workflow expectations": red-green TDD, plan before edits (this document), manual UI validation before considering a task done, PR at the end.
- Swift default actor isolation is MainActor (`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`); only mark a declaration `nonisolated` when it's called from a non-MainActor context. `RootDestination` is only ever called from `RootView` (a View, MainActor) and a `@MainActor` test suite, so it stays a plain (implicitly MainActor) enum — do not add `nonisolated`.
- User-facing copy goes through `CopyKey`/`Shared/Copy.xcstrings` (the `Copy` string table), never a raw `Text("…")` literal — see `Shared/Copy/CopyKey.swift:290-295`.
- Accessibility identifiers on SwiftUI containers need `.accessibilityElement(children: .combine)` to be queryable; plain `Text`/`Button` elements don't need it. Don't add an identifier to a container unless it actually needs to be queried as one unit.
- Every commit needs a `Co-Authored-By:` trailer naming the specific agent, e.g. `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` for implementer-agent commits.
- Reference spec: `Docs/Agents/Specs/SCREEN_TIME_ACCESS_REQUIRED_OVERLAY.md`.

---

### Task 1: `RootDestination` pure decision logic

**Files:**
- Create: `OpenAppLock/Logic/RootDestination.swift`
- Test: `OpenAppLockTests/RootDestinationTests.swift`

**Interfaces:**
- Consumes: `ScreenTimeAuthorizationStatus` (existing, `OpenAppLock/Services/ScreenTimeAuthorization.swift:10-14`) with cases `.notDetermined`, `.denied`, `.approved`.
- Produces: `enum RootDestination: Equatable { case onboarding, screenTimeAccessRequired, main }` with `static func resolve(hasCompletedOnboarding: Bool, authorizationStatus: ScreenTimeAuthorizationStatus) -> RootDestination` — consumed by Task 3.

- [ ] **Step 1: Write the failing test**

Create `OpenAppLockTests/RootDestinationTests.swift`:

```swift
//
//  RootDestinationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@MainActor
@Suite("Root destination resolution")
struct RootDestinationTests {
    @Test(
        "Onboarding incomplete always routes to onboarding, regardless of authorization",
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
            .approved,
        ]
    )
    func onboardingIncomplete(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: false, authorizationStatus: status
        )
        #expect(destination == .onboarding)
    }

    @Test("Onboarding complete with approved authorization routes to main")
    func onboardingCompleteApproved() {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true, authorizationStatus: .approved
        )
        #expect(destination == .main)
    }

    @Test(
        "Onboarding complete without approval routes to the access-required screen",
        arguments: [
            ScreenTimeAuthorizationStatus.notDetermined,
            .denied,
        ]
    )
    func onboardingCompleteNotApproved(status: ScreenTimeAuthorizationStatus) {
        let destination = RootDestination.resolve(
            hasCompletedOnboarding: true, authorizationStatus: status
        )
        #expect(destination == .screenTimeAccessRequired)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run via the Xcode MCP `RunSomeTests` tool, targeting `OpenAppLockTests/RootDestinationTests`.
Expected: FAIL — compile error, `RootDestination` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `OpenAppLock/Logic/RootDestination.swift`:

```swift
//
//  RootDestination.swift
//  OpenAppLock
//

import Foundation

/// Derives which top-level screen `RootView` should show from onboarding
/// completion and current Screen Time authorization. Both `.notDetermined`
/// and `.denied` map to `.screenTimeAccessRequired`: once onboarding is
/// complete, either status means the app can no longer enforce anything, and
/// the only fix in both cases is the same visit to Settings.
enum RootDestination: Equatable {
    case onboarding
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        return authorizationStatus == .approved ? .main : .screenTimeAccessRequired
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run via the Xcode MCP `RunSomeTests` tool, targeting `OpenAppLockTests/RootDestinationTests`.
Expected: PASS, all 6 cases.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Logic/RootDestination.swift OpenAppLockTests/RootDestinationTests.swift
git commit -m "feat: add RootDestination to derive the root screen from onboarding + auth status

Co-Authored-By: <agent name> <noreply@anthropic.com>"
```

---

### Task 2: Copy keys + `ScreenTimeAccessRequiredView`

**Files:**
- Modify: `Shared/Copy/CopyKey.swift` (append new cases before the `resource`/`string` computed properties, around line 288-290)
- Modify: `Shared/Copy.xcstrings` (insert new entries alphabetically, immediately before the `"selectionMode.allowOnly"` entry at line 1874)
- Create: `OpenAppLock/Views/ScreenTimeAccessRequiredView.swift`

**Interfaces:**
- Consumes: nothing from other tasks (self-contained view + copy).
- Produces: `struct ScreenTimeAccessRequiredView: View` (no init parameters) — consumed by Task 3. Accessibility identifiers `screenTimeAccessRequiredTitle` (on the title `Text`) and `screenTimeAccessOpenSettingsButton` (on the `Button`) — consumed by Task 4's UI test.

- [ ] **Step 1: Add copy keys to `CopyKey.swift`**

In `Shared/Copy/CopyKey.swift`, insert a new section right before the `resource`/`string`/`string(_:)` computed properties (i.e. right after the last existing `case` line, `case appListsDeleteConfirmationMessage = "appLists.deleteConfirmationMessage"`):

```swift
    // MARK: - ScreenTimeAccessRequiredView
    case screenTimeAccessTitle = "screenTimeAccess.title"
    case screenTimeAccessDescription = "screenTimeAccess.description"
    case screenTimeAccessOpenSettingsButton = "screenTimeAccess.openSettingsButton"
```

- [ ] **Step 2: Add the string entries to `Copy.xcstrings`**

In `Shared/Copy.xcstrings`, find this block (ends at line 1873):

```json
    "rulesList.ruleLimitAlertTitle" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rule limit reached"
          }
        }
      }
    },
    "selectionMode.allowOnly" : {
```

Replace it with (inserting the three new keys between them, alphabetically ordered — `screenTimeAccess.description` < `screenTimeAccess.openSettingsButton` < `screenTimeAccess.title` < `selectionMode.allowOnly`):

```json
    "rulesList.ruleLimitAlertTitle" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Rule limit reached"
          }
        }
      }
    },
    "screenTimeAccess.description" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "OpenAppLock can't block anything without Screen Time access. Turn it back on in Settings to keep your rules working."
          }
        }
      }
    },
    "screenTimeAccess.openSettingsButton" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Open Settings"
          }
        }
      }
    },
    "screenTimeAccess.title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Screen Time Access Needed"
          }
        }
      }
    },
    "selectionMode.allowOnly" : {
```

- [ ] **Step 3: Create the view**

Create `OpenAppLock/Views/ScreenTimeAccessRequiredView.swift`:

```swift
//
//  ScreenTimeAccessRequiredView.swift
//  OpenAppLock
//

import SwiftUI

/// Full-screen block shown by `RootView` whenever Screen Time access was
/// granted during onboarding but is not currently approved (revoked or reset
/// from system Settings). The app can't enforce any rule without it, so this
/// replaces `MainView` entirely rather than layering on top of it — see
/// `RootDestination.resolve`. Returning to `MainView` happens automatically:
/// `RootView` re-checks authorization on every foreground.
struct ScreenTimeAccessRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(.screenTimeAccessTitle)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("screenTimeAccessRequiredTitle")
            Text(.screenTimeAccessDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(.screenTimeAccessOpenSettingsButton)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("screenTimeAccessOpenSettingsButton")
        }
        .padding()
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run via the Xcode MCP `BuildProject` tool (simulator destination).
Expected: build succeeds, no errors/warnings from the new file.

- [ ] **Step 5: Commit**

```bash
git add Shared/Copy/CopyKey.swift Shared/Copy.xcstrings OpenAppLock/Views/ScreenTimeAccessRequiredView.swift
git commit -m "feat: add ScreenTimeAccessRequiredView for revoked Screen Time access

Co-Authored-By: <agent name> <noreply@anthropic.com>"
```

---

### Task 3: Wire `RootView` to the new destination

**Files:**
- Modify: `OpenAppLock/Views/RootView.swift` (full file, currently 39 lines)

**Interfaces:**
- Consumes: `RootDestination.resolve` (Task 1), `ScreenTimeAccessRequiredView` (Task 2), existing `ScreenTimeAuthorization.status` (`OpenAppLock/Services/ScreenTimeAuthorization.swift:63`), existing `Diag.log(_:_:)` (used elsewhere via `Diag.log(.lifecycle, "…")`, e.g. `OpenAppLock/Views/MainView.swift:33`).
- Produces: nothing new consumed by later tasks — this is the integration point.

- [ ] **Step 1: Replace `RootView.swift`**

Replace the full contents of `OpenAppLock/Views/RootView.swift` with:

```swift
//
//  RootView.swift
//  OpenAppLock
//

import SwiftUI

/// Gates the app on onboarding and on Screen Time authorization: until the
/// user has walked through the welcome and permission steps, nothing else is
/// reachable, and if access is later revoked from system Settings,
/// `MainView` is replaced by `ScreenTimeAccessRequiredView` until access is
/// restored. See `RootDestination.resolve` for the exact rule.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(ScreenTimeAuthorization.self) private var authorization
    @Environment(NotificationAuthorization.self) private var notificationAuthorization
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch RootDestination.resolve(
                hasCompletedOnboarding: hasCompletedOnboarding,
                authorizationStatus: authorization.status
            ) {
            case .onboarding:
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            case .screenTimeAccessRequired:
                ScreenTimeAccessRequiredView()
                    .onAppear {
                        Diag.log(
                            .lifecycle,
                            "screen time authorization not approved — showing access-required overlay"
                        )
                    }
            case .main:
                MainView()
            }
        }
        // Keep authorization state current app-wide: refresh at launch and on
        // every foreground, so permission changes made in the system Settings app
        // — including a notification revocation — are reflected everywhere, not
        // only when the user opens a screen that happens to read them. Notification
        // status is also mirrored into the app group here, so the scheduler keeps
        // the time-limit warn activity registered without a Settings visit.
        .task { await notificationAuthorization.refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            authorization.refresh()
            Task { await notificationAuthorization.refresh() }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run via the Xcode MCP `BuildProject` tool (simulator destination).
Expected: build succeeds.

- [ ] **Step 3: Run the full unit test suite**

Run via the Xcode MCP `RunAllTests` tool (unit test target only, or full suite — implementer's call given time budget, but at minimum `OpenAppLockTests`).
Expected: PASS, no regressions.

- [ ] **Step 4: Commit**

```bash
git add OpenAppLock/Views/RootView.swift
git commit -m "feat: gate RootView on Screen Time authorization, not just onboarding

Co-Authored-By: <agent name> <noreply@anthropic.com>"
```

---

### Task 4: UI-test harness support + UI test

**Files:**
- Modify: `OpenAppLock/Services/LaunchConfiguration.swift`
- Modify: `OpenAppLock/OpenAppLockApp.swift` (lines 80-85)
- Modify: `OpenAppLockUITests/UITestSupport.swift` (lines 15-40)
- Create: `OpenAppLockUITests/ScreenTimeAccessRequiredUITests.swift`

**Interfaces:**
- Consumes: `MockAuthorizationProvider(status:requestShouldFail:)` (existing, `OpenAppLock/Services/ScreenTimeAuthorization.swift:40-58`), accessibility identifiers from Task 2 (`screenTimeAccessRequiredTitle`, `screenTimeAccessOpenSettingsButton`), existing `newRuleButton`/`waitForMainUI()` identifiers.
- Produces: `LaunchConfiguration.screenTimeAccessRevoked: Bool`, launch flag `-screen-time-access-revoked`, `XCUIApplication.launchOpenAppLock(..., screenTimeAccessRevoked: Bool = false)` — nothing consumed by later tasks (this is the last task).

- [ ] **Step 1: Add the launch flag to `LaunchConfiguration`**

In `OpenAppLock/Services/LaunchConfiguration.swift`, add a new property next to `notificationsAuthorized`:

```swift
    /// Seeds the mock notification authorization as already-granted, so a UI test
    /// can exercise the authorized state directly. Absent → `.notDetermined`, so
    /// the grant transition is the default path under test.
    var notificationsAuthorized = false
    /// Forces the mock Screen Time authorization to `.denied` even when onboarding
    /// is completed, so a UI test can exercise the post-onboarding
    /// access-required screen. Absent → the existing `.approved` default.
    var screenTimeAccessRevoked = false
```

Add the matching flag constant next to `notificationsAuthorizedFlag`:

```swift
    static let notificationsAuthorizedFlag = "-notifications-authorized"
    static let screenTimeAccessRevokedFlag = "-screen-time-access-revoked"
```

Add the parse line next to `config.notificationsAuthorized = ...`:

```swift
        config.notificationsAuthorized = arguments.contains(notificationsAuthorizedFlag)
        config.screenTimeAccessRevoked = arguments.contains(screenTimeAccessRevokedFlag)
```

- [ ] **Step 2: Wire the flag into the mock authorization provider**

In `OpenAppLock/OpenAppLockApp.swift`, replace:

```swift
        let authProvider: AuthorizationProviding =
            config.isUITesting
            ? MockAuthorizationProvider(
                status: config.onboardingCompleted == false ? .notDetermined : .approved
            )
            : FamilyControlsAuthorizationProvider()
```

with:

```swift
        let authProvider: AuthorizationProviding =
            config.isUITesting
            ? MockAuthorizationProvider(
                status: config.onboardingCompleted == false
                    ? .notDetermined
                    : (config.screenTimeAccessRevoked ? .denied : .approved)
            )
            : FamilyControlsAuthorizationProvider()
```

- [ ] **Step 3: Add the launch helper parameter**

In `OpenAppLockUITests/UITestSupport.swift`, replace the `launchOpenAppLock` signature and body:

```swift
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
```

- [ ] **Step 4: Write the UI test**

Create `OpenAppLockUITests/ScreenTimeAccessRequiredUITests.swift`:

```swift
//
//  ScreenTimeAccessRequiredUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class ScreenTimeAccessRequiredUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRevokedAuthorizationShowsAccessRequiredScreen() throws {
        let app = XCUIApplication.launchOpenAppLock(
            onboardingCompleted: true, screenTimeAccessRevoked: true
        )

        app.element("screenTimeAccessRequiredTitle").waitToAppear()
        XCTAssertTrue(app.buttons["screenTimeAccessOpenSettingsButton"].exists)
        XCTAssertFalse(app.buttons["newRuleButton"].exists)
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
    }

    func testApprovedAuthorizationShowsMainApp() throws {
        let app = XCUIApplication.launchOpenAppLock(onboardingCompleted: true)

        app.waitForMainUI()
        XCTAssertFalse(app.buttons["screenTimeAccessOpenSettingsButton"].exists)
    }
}
```

- [ ] **Step 5: Run the new UI tests**

Run via the Xcode MCP `RunSomeTests` tool, targeting `OpenAppLockUITests/ScreenTimeAccessRequiredUITests`, on an iOS simulator destination.
Expected: both tests PASS.

- [ ] **Step 6: Run the full test suite**

Run via the Xcode MCP `RunAllTests` tool.
Expected: PASS, no regressions (watch in particular for the flaky suites noted in project memory — `RuleSchedulerTests`/`NotificationSettingsUITests` — re-run once before treating a failure there as real).

- [ ] **Step 7: Manual on-device/simulator validation**

Launch the app on a simulator with onboarding completed and Screen Time access granted, then use the Settings app to revoke OpenAppLock's Screen Time access, foreground OpenAppLock again, and confirm the access-required screen appears and "Open Settings" opens the correct Settings page. If Xcode/simulator tooling isn't reachable in this session, say so explicitly rather than skipping silently.

- [ ] **Step 8: Commit**

```bash
git add OpenAppLock/Services/LaunchConfiguration.swift OpenAppLock/OpenAppLockApp.swift OpenAppLockUITests/UITestSupport.swift OpenAppLockUITests/ScreenTimeAccessRequiredUITests.swift
git commit -m "test: add UI-test coverage for the screen-time access-required screen

Co-Authored-By: <agent name> <noreply@anthropic.com>"
```
