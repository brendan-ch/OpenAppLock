# Rule Hard Cap (10) + N=1 Time-Limit Arming — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap the app at 10 rules with an alert on the 11th, and arm time-limit rules for today only (N=1) so the DeviceActivity midnight self-arm can be trialed on device.

**Architecture:** A pure `RuleCreationPolicy` holds the cap; `RulesListView` routes both New-Rule buttons through it, showing an alert when full. `RuleScheduler.dayActivityHorizon` drops 2→1. A new `at-rule-cap` UI-test seed scenario seeds exactly 10 rules to prove the alert.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, DeviceActivity/FamilyControls; Swift Testing (`import Testing`) for unit tests, XCTest for UI tests; String Catalog (`Copy.xcstrings`).

## Global Constraints

- Base: `origin/main` @ `175cf00` (v1.0.2). Branch: `feat/rules-hard-cap`.
- Build/test **only** via the Xcode MCP (`XcodeListWindows` for the tab id, then `BuildProject` / `RunSomeTests`); scheme destination **must be an iOS simulator**. Never `xcodebuild`. If the Xcode MCP / simulator is unreachable this session, say so and hand test/UI verification back to the user.
- Unit tests are `@MainActor` structs (the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`); go through `makeInMemoryContext()` (TestSupport.swift) for any SwiftData work — never build ad-hoc `ModelContainer`s.
- Every `CopyKey` case MUST have a `Copy.xcstrings` entry (`CopyCatalogTests.everyKeyResolvesToACatalogValue`), and every copy value MUST use smart typography — no straight `'`, no straight `"`, no literal `...` (`CopyCatalogTests.everyValueUsesSmartTypography`).
- Cap value is **10**, single source of truth `RuleCreationPolicy.maxRuleCount`.
- Conventional commits; end every commit message with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Commit only when the user asks — the per-task "Commit" steps below are staged for that go-ahead.
- Xcode file-system-synchronized groups: adding a `.swift` file on disk is enough (no pbxproj edit).

---

### Task 1: `RuleCreationPolicy` (pure cap)

**Files:**
- Create: `OpenAppLock/Logic/RuleCreationPolicy.swift`
- Test: `OpenAppLockTests/RuleCreationPolicyTests.swift`

**Interfaces:**
- Produces: `enum RuleCreationPolicy { static let maxRuleCount: Int (== 10); static func canCreateRule(existingRuleCount: Int) -> Bool }`

- [ ] **Step 1: Write the failing test**

Create `OpenAppLockTests/RuleCreationPolicyTests.swift`:

```swift
//
//  RuleCreationPolicyTests.swift
//  OpenAppLockTests
//

import Testing
@testable import OpenAppLock

@MainActor
struct RuleCreationPolicyTests {
    @Test func capIsTen() {
        #expect(RuleCreationPolicy.maxRuleCount == 10)
    }

    @Test func allowsCreationBelowTheCap() {
        #expect(RuleCreationPolicy.canCreateRule(existingRuleCount: 0))
        #expect(RuleCreationPolicy.canCreateRule(existingRuleCount: 9))
    }

    @Test func blocksCreationAtOrAboveTheCap() {
        #expect(!RuleCreationPolicy.canCreateRule(existingRuleCount: 10))
        #expect(!RuleCreationPolicy.canCreateRule(existingRuleCount: 11))
    }
}
```

- [ ] **Step 2: Run the test — verify it fails**

Run (Xcode MCP `RunSomeTests`, tab id from `XcodeListWindows`): `OpenAppLockTests/RuleCreationPolicyTests`
Expected: FAIL — compile error "cannot find 'RuleCreationPolicy' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `OpenAppLock/Logic/RuleCreationPolicy.swift`:

```swift
//
//  RuleCreationPolicy.swift
//  OpenAppLock
//

/// Whether a new rule may be created, given how many already exist.
///
/// A hard cap keeps the app within Apple's ~20 concurrent-DeviceActivity ceiling:
/// with N=1 time-limit arming (`RuleScheduler.dayActivityHorizon`) the worst case
/// is 2 activities per rule (a nudge-on time limit: one block + one warn), so
/// 10 rules → 20 activities. Counts ALL rules, enabled or not — a safe
/// over-approximation that needs no separate cap on enabling a rule.
enum RuleCreationPolicy {
    static let maxRuleCount = 10

    static func canCreateRule(existingRuleCount: Int) -> Bool {
        existingRuleCount < maxRuleCount
    }
}
```

- [ ] **Step 4: Run the test — verify it passes**

Run: `OpenAppLockTests/RuleCreationPolicyTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Logic/RuleCreationPolicy.swift OpenAppLockTests/RuleCreationPolicyTests.swift
git commit -m "feat: add RuleCreationPolicy with a 10-rule hard cap"
```

---

### Task 2: N=1 time-limit arming

Flip `dayActivityHorizon` 2→1. TDD for a constant/behavior change: first retarget the tests that encode N=2 so they fail against the current code, then flip the constant to make them pass, then update the docs the behavior owns.

**Files:**
- Modify: `OpenAppLock/Services/RuleScheduler.swift` (`:53` constant + doc comments `:50-53`, `:179-184`)
- Modify test: `OpenAppLockTests/SchedulingTests.swift` (funcs at `:189`, `:211`, `:227`, `:426`)
- Modify test: `OpenAppLockTests/RuleSchedulerWarnTests.swift` (func at `:92`, assertions `:104`,`:112`,`:120`)
- Modify docs: `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` (§5, §10, §13/§14), `AGENTS.md` (time-limit day-keyed "Known gaps" bullet)

**Interfaces:**
- Consumes: nothing new.
- Produces: `RuleScheduler.dayActivityHorizon == 1`.

- [ ] **Step 1: Retarget the N=2 assertions to N=1**

In `OpenAppLockTests/RuleSchedulerWarnTests.swift`, `togglingNudgeLeavesBlockActivityUntouched`:
- Line ~102 comment → `// Nudge off: only today's single block activity starts.`
- Line ~104: `#expect(monitor.startCallCount == 2)` → `#expect(monitor.startCallCount == 1)`
- Line ~107-108 comment → `// Turn the nudge on and re-sync: one warn activity is added (one more // start); the block activity is NOT restarted.`
- Line ~112: `#expect(monitor.startCallCount == 4)` → `#expect(monitor.startCallCount == 2)`
- Line ~116-117 comment → `// Turn it back off: the warn activity is stopped, block still present and // never restarted (start count unchanged).`
- Line ~120: `#expect(monitor.startCallCount == 4)` → `#expect(monitor.startCallCount == 2)`

In `OpenAppLockTests/SchedulingTests.swift`, replace the four affected tests with their N=1 forms:

`timeLimitArmsTwoDayKeyedActivities` (`:188-208`) → today-only:

```swift
    @Test("A time limit arms a per-day block activity for today only (N=1)")
    func timeLimitArmsTodayOnly() throws {
        let (scheduler, monitor, store) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)

        scheduler.sync(rules: [rule], at: now, calendar: utc)

        let today = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))
        let tomorrow = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 7), calendar: utc))
        #expect(monitor.monitoredNames.contains(today))
        // N=1: the next day is armed only by the monitor self-arm, not in the foreground.
        #expect(!monitor.monitoredNames.contains(tomorrow))
        #expect(
            monitor.startedEvents[today]?[MonitoringPlan.minuteEventName(for: rule.dailyLimitMinutes)]
                == rule.dailyLimitMinutes)
        // No legacy un-keyed daily activity is armed for a time limit.
        #expect(!monitor.monitoredNames.contains("rule-\(rule.id.uuidString)"))
        #expect(store.snapshot(for: rule.id) != nil)
    }
```

`dayRolloverReapsPastActivity` (`:210-224`) → arms one day, reaps the previous:

```swift
    @Test("Rolling the day forward arms the new day and reaps the previous day")
    func dayRolloverReapsPastActivity() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")

        scheduler.sync(rules: [rule], at: date(2025, 1, 6, 10, 0), calendar: utc)  // arms 01-06
        scheduler.sync(rules: [rule], at: date(2025, 1, 7, 10, 0), calendar: utc)  // arms 01-07, reaps 01-06

        let jan6 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))
        let jan7 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 7), calendar: utc))
        let jan8 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 8), calendar: utc))
        #expect(!monitor.monitoredNames.contains(jan6))  // reaped
        #expect(monitor.monitoredNames.contains(jan7))   // today
        #expect(!monitor.monitoredNames.contains(jan8))  // N=1: next day not pre-armed
    }
```

`adoptsSelfArmedActivity` (`:226-250`) → adopting today arms nothing new:

```swift
    @Test("A background self-armed activity is adopted, not restarted, by the next sync")
    func adoptsSelfArmedActivity() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)
        let todayName = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: utc))

        // Simulate the monitor having self-armed today's activity in the
        // background: it is monitored, but the scheduler recorded no fingerprint.
        try monitor.startDayMonitoring(
            name: todayName, from: date(2025, 1, 6), to: date(2025, 1, 7),
            selectionData: Data([1]),
            eventMinutes: MonitoringPlan.blockEvent(forLimit: rule.dailyLimitMinutes))
        let startsAfterSelfArm = monitor.startCallCount  // 1

        scheduler.sync(rules: [rule], at: now, calendar: utc)
        // Today's activity is adopted (not restarted → its live count is kept),
        // and N=1 means there is no next day to arm — no new start.
        #expect(monitor.startCallCount == startsAfterSelfArm)

        // A second sync also leaves today's alone (its fingerprint was recorded).
        scheduler.sync(rules: [rule], at: now, calendar: utc)
        #expect(monitor.startCallCount == startsAfterSelfArm)
    }
```

`avoidsRestartChurn` (`:425-438`) → one day activity:

```swift
        scheduler.sync(rules: [rule], at: now, calendar: utc)
        scheduler.sync(rules: [rule], at: now, calendar: utc)
        #expect(monitor.startCallCount == 1)  // today only, started once

        rule.dailyLimitMinutes = 60
        scheduler.sync(rules: [rule], at: now, calendar: utc)
        #expect(monitor.startCallCount == 2)  // the one day activity restarts on budget change
```

- [ ] **Step 2: Run the retargeted tests — verify they fail**

Run: `OpenAppLockTests/SchedulingTests` and `OpenAppLockTests/RuleSchedulerWarnTests`
Expected: FAIL — the current N=2 code arms two days (e.g. `startCallCount == 2` where the test now wants `1`; `tomorrow` is present where the test now wants it absent).

- [ ] **Step 3: Flip the horizon to 1 and update the doc comment**

In `OpenAppLock/Services/RuleScheduler.swift`, replace the `dayActivityHorizon` declaration + doc comment (`:50-53`):

```swift
    /// How many upcoming scheduled days a time-limit rule arms ahead. **N = 1**:
    /// only the current-or-next scheduled day is armed in the foreground; the day
    /// after is armed solely by the monitor's midnight self-arm
    /// (`DeviceActivityMonitorExtension.reArmNextScheduledDay`). This is a
    /// deliberate device trial of that unverified self-arm — dropping the old
    /// N = 2 foreground buffer both halves the per-rule activity cost (so the
    /// 10-rule `RuleCreationPolicy` cap fits Apple's ~20 ceiling) and makes the
    /// self-arm's real-device reliability observable. See the day-keyed
    /// enforcement spec §5 and `RULE_HARD_CAP_AND_N1_ARMING.md`.
    static let dayActivityHorizon = 1
```

Then update the `dayPlans` doc comment (`:179-184`) so it reads "across the current-or-next scheduled day (N = 1)" instead of "next `dayActivityHorizon` scheduled days … the next day is armed before its midnight".

- [ ] **Step 4: Run the tests — verify they pass**

Run: `OpenAppLockTests/SchedulingTests` and `OpenAppLockTests/RuleSchedulerWarnTests`
Expected: PASS.

- [ ] **Step 5: Update the spec + AGENTS.md (same change)**

- `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md`: §5 — the foreground net is now N = 1 (today only); the self-arm is the sole next-day path. §10 — budget table is now ~2 per nudge-on rule, ~10 rules to the ceiling. §13/§14 — note the multi-day-closed lapse now begins after one day and the self-arm is load-bearing (cross-link `RULE_HARD_CAP_AND_N1_ARMING.md`).
- `AGENTS.md`: in the time-limit day-keyed "Known gaps" bullet, change "armed for the next two scheduled days" to "armed for the current scheduled day only (N = 1)" and note the 10-rule cap.

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Services/RuleScheduler.swift OpenAppLockTests/SchedulingTests.swift \
  OpenAppLockTests/RuleSchedulerWarnTests.swift \
  Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md AGENTS.md
git commit -m "feat: arm time-limit rules for today only (N=1) to trial the midnight self-arm"
```

---

### Task 3: Copy strings + `at-rule-cap` seed scenario

**Files:**
- Create test: `OpenAppLockTests/SampleRulesTests.swift`
- Modify: `OpenAppLock/Services/LaunchConfiguration.swift` (add `SeedScenario` case)
- Modify: `OpenAppLock/Services/SampleRules.swift` (seed 10 rules for the new case)
- Modify: `Shared/Copy/CopyKey.swift` (2 cases)
- Modify: `Shared/Copy.xcstrings` (2 entries)

**Interfaces:**
- Consumes: `RuleCreationPolicy.maxRuleCount` (Task 1).
- Produces: `LaunchConfiguration.SeedScenario.atRuleCap` (rawValue `"at-rule-cap"`); `CopyKey.rulesListRuleLimitAlertTitle`, `CopyKey.rulesListRuleLimitAlertMessage`.

- [ ] **Step 1: Write the failing seed test**

Create `OpenAppLockTests/SampleRulesTests.swift`:

```swift
//
//  SampleRulesTests.swift
//  OpenAppLockTests
//

import SwiftData
import Testing
@testable import OpenAppLock

@MainActor
struct SampleRulesTests {
    @Test func atRuleCapSeedsExactlyTheCapCount() throws {
        let context = try makeInMemoryContext()
        SampleRules.seed(.atRuleCap, into: context)
        let rules = try context.fetch(FetchDescriptor<BlockingRule>())
        #expect(rules.count == RuleCreationPolicy.maxRuleCount)  // 10
    }
}
```

- [ ] **Step 2: Run the test — verify it fails**

Run: `OpenAppLockTests/SampleRulesTests`
Expected: FAIL — compile error "type 'LaunchConfiguration.SeedScenario' has no member 'atRuleCap'".

- [ ] **Step 3: Add the seed scenario case + seeding**

In `OpenAppLock/Services/LaunchConfiguration.swift`, add to the `SeedScenario` enum (after `case limits`, `:19`):

```swift
        /// Ten rules — exactly `RuleCreationPolicy.maxRuleCount` — so the New Rule
        /// button trips the rule-limit alert.
        case atRuleCap = "at-rule-cap"
```

In `OpenAppLock/Services/SampleRules.swift`, add a `case` to the `switch scenario` (the switch is exhaustive, so this is compiler-required):

```swift
        case .atRuleCap:
            rules = (1...RuleCreationPolicy.maxRuleCount).map { index in
                BlockingRule(
                    name: String(format: "Rule %02d", index),
                    configuration: .schedule(
                        ScheduleConfig(startMinutes: 9 * 60, endMinutes: 17 * 60)),
                    days: Weekday.everyDay)
            }
```

(The existing `for rule in rules { context.insert(rule); rule.appList = distractions }` tail inserts and wires all ten.)

- [ ] **Step 4: Run the test — verify it passes**

Run: `OpenAppLockTests/SampleRulesTests`
Expected: PASS.

- [ ] **Step 5: Add the copy keys**

The two `Copy.xcstrings` entries are **already present in the working tree** — the controller added them via Xcode's exact String-Catalog format (`"key" : {`, 2-space indent, sorted position), because Python `json.dump` would reformat all 2448 lines and the Xcode `StringCatalogEdit` MCP tool is translation-oriented. Values: `rulesList.ruleLimitAlertTitle` = "Rule limit reached"; `rulesList.ruleLimitAlertMessage` = "You can have up to %lld rules. Delete one to add another." (smart typography, no straight quotes/apostrophes/ellipsis). **Do NOT edit `Shared/Copy.xcstrings`.**

In `Shared/Copy/CopyKey.swift`, add after `case rulesListEmptyStateDescription`:

```swift
    case rulesListRuleLimitAlertTitle = "rulesList.ruleLimitAlertTitle"
    case rulesListRuleLimitAlertMessage = "rulesList.ruleLimitAlertMessage"
```

- [ ] **Step 6: Controller verifies the catalog invariant**

Controller runs: `OpenAppLockTests/CopyCatalogTests`
Expected: PASS — the new keys resolve to their (already-present) catalog values and use smart typography. (If it FAILS with "Missing catalog entry", the CopyKey raw value and the catalog key are mismatched — fix the `CopyKey` case, not the catalog.)

- [ ] **Step 7: Commit**

```bash
git add OpenAppLock/Services/LaunchConfiguration.swift OpenAppLock/Services/SampleRules.swift \
  OpenAppLockTests/SampleRulesTests.swift Shared/Copy/CopyKey.swift Shared/Copy.xcstrings
git commit -m "feat: add rule-limit alert copy and at-rule-cap seed scenario"
```

---

### Task 4: `RulesListView` cap wiring + UI test

**Files:**
- Create test: `OpenAppLockUITests/RuleLimitUITests.swift`
- Modify: `OpenAppLock/Views/Rules/RulesListView.swift`

**Interfaces:**
- Consumes: `RuleCreationPolicy.canCreateRule(existingRuleCount:)` and `.maxRuleCount` (Task 1); `CopyKey.rulesListRuleLimitAlert*` and `SeedScenario` `"at-rule-cap"` (Task 3); existing `newRuleButton` id and `app.goToRulesTab()` helper.

- [ ] **Step 1: Write the failing UI test**

Create `OpenAppLockUITests/RuleLimitUITests.swift`:

```swift
//
//  RuleLimitUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class RuleLimitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAlertShownWhenAtRuleCap() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "at-rule-cap")
        app.goToRulesTab()

        app.buttons["newRuleButton"].waitToAppear().tap()

        // The cap alert appears and the New Rule sheet does not.
        app.alerts["Rule limit reached"].waitToAppear()
        XCTAssertFalse(app.staticTexts["New Rule"].exists)
        app.alerts.buttons["OK"].tap()
    }

    func testNoAlertBelowRuleCap() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()

        app.buttons["newRuleButton"].waitToAppear().tap()

        // Below the cap the New Rule sheet opens and no alert shows.
        app.staticTexts["New Rule"].waitToAppear()
        XCTAssertFalse(app.alerts["Rule limit reached"].exists)
    }
}
```

- [ ] **Step 2: Run the UI test — verify it fails**

Run: `OpenAppLockUITests/RuleLimitUITests`
Expected: FAIL — `testAlertShownWhenAtRuleCap` fails because tapping `newRuleButton` currently opens the "New Rule" sheet instead of the alert (`testNoAlertBelowRuleCap` already passes).

- [ ] **Step 3: Wire the cap into `RulesListView`**

In `OpenAppLock/Views/Rules/RulesListView.swift`:

Add state after `@State private var showingNewRule = false` (`:18`):

```swift
    @State private var showingRuleLimitAlert = false
```

Change the toolbar button action (`:28-30`) from `{ showingNewRule = true }` to `{ attemptNewRule() }`:

```swift
                    Button(CopyKey.rulesListNewRuleButton.resource, systemImage: "plus") {
                        attemptNewRule()
                    }
```

Change the empty-state button action (`:55-57`) from `{ showingNewRule = true }` to `{ attemptNewRule() }`:

```swift
                Button(CopyKey.rulesListNewRuleButton.resource) {
                    attemptNewRule()
                }
```

Add the alert after the `.sheet(isPresented: $showingNewRule) { NewRuleSheet() }` block (`:38-40`):

```swift
        .alert(
            Text(CopyKey.rulesListRuleLimitAlertTitle.resource),
            isPresented: $showingRuleLimitAlert
        ) {
            Button(CopyKey.appListsOkButtonLabel.resource, role: .cancel) {}
        } message: {
            Text(CopyKey.rulesListRuleLimitAlertMessage.string(RuleCreationPolicy.maxRuleCount))
        }
```

Add the routing helper (e.g. just before `rulesList(now:)`):

```swift
    /// Presents the New Rule sheet, or the cap alert when the rule limit is
    /// reached (see `RuleCreationPolicy`). Both the toolbar and empty-state
    /// buttons route through here.
    private func attemptNewRule() {
        if RuleCreationPolicy.canCreateRule(existingRuleCount: rules.count) {
            showingNewRule = true
        } else {
            showingRuleLimitAlert = true
        }
    }
```

- [ ] **Step 4: Run the UI test — verify it passes**

Run: `OpenAppLockUITests/RuleLimitUITests`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Views/Rules/RulesListView.swift OpenAppLockUITests/RuleLimitUITests.swift
git commit -m "feat: block creating an 11th rule with a rule-limit alert"
```

---

### Task 5: Full-suite verification + manual UI check

**Files:** none (verification only).

- [ ] **Step 1: Build**

Run (Xcode MCP `BuildProject`): expected BUILD SUCCEEDED, no new warnings (audit `GetBuildLog` severity=warning too — Swift-6-mode warnings are future errors).

- [ ] **Step 2: Run the whole suite**

Run (Xcode MCP `RunAllTests`): expected PASS. If `RuleSchedulerTests`/`NotificationSettingsUITests` flake under a full parallel run, re-run them in isolation before treating it as a regression.

- [ ] **Step 3: Manual UI validation (simulator)**

Launch the app on a simulator; create rules to 10, confirm the 11th tap shows "Rule limit reached" and the editor never opens; delete one and confirm New Rule works again. If the Xcode MCP / simulator is unreachable this session, state that explicitly and hand this step back to the user.

- [ ] **Step 4: Push + open PR (only when the user asks)**

```bash
git push -u origin feat/rules-hard-cap
gh pr create --base main --title "Rule hard cap (10) + N=1 time-limit arming" --body "<summary + test plan + Claude Code footer>"
```

---

## Self-Review

**Spec coverage:** Part A (N=1) → Task 2. Part B (`RuleCreationPolicy` → Task 1; `RulesListView` wiring + alert → Task 4; copy → Task 3). Part C (policy unit test → Task 1; N=1 test updates → Task 2; seed scenario + seed test → Task 3; `RuleLimitUITests` → Task 4). Docs → Task 2. Full-suite + manual + PR → Task 5. No gaps.

**Placeholder scan:** none — every code step shows full code; the one PR body is intentionally author-filled at push time.

**Type consistency:** `RuleCreationPolicy.maxRuleCount` / `canCreateRule(existingRuleCount:)`, `SeedScenario.atRuleCap` = `"at-rule-cap"` (matches the UI test string), `CopyKey.rulesListRuleLimitAlertTitle` / `rulesListRuleLimitAlertMessage`, and `RuleScheduler.dayActivityHorizon` are used identically across tasks.
