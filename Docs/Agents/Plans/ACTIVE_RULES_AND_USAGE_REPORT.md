# Active Rules + per-rule DeviceActivityReport — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the broken "Xm of Ym used" live counter, rename Home's "Usage" section to "Active Rules" with tappable rows, and embed a per-rule `DeviceActivityReport` (rendering today's total usage) in the rule-detail overlay.

**Architecture:** The live count was fed by a DeviceActivityReport extension writing an "authoritative" total into the app group — a write the extension's sandbox blocks on device, so the number never updated. We remove that whole path and instead render usage *inside* the report extension's own view (the only supported way), embedded in `RuleDetailSheet`. The block decision keeps its single `minutes-<budget>` event and now reads `minutesUsed` directly.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, FamilyControls / DeviceActivity / ManagedSettings (Screen Time), Swift Testing (`@Test`/`#expect`), XCUITest.

## Global Constraints

- **Build/test only via the Xcode MCP** (`BuildProject`, `RunSomeTests`, `RunAllTests`) — never raw `xcodebuild`. Get the window/tab id from `XcodeListWindows`. Scheme destination must be an iOS **Simulator** (a device destination hangs test runs).
- **Unit tests:** Swift Testing (`import Testing`, `@Test`, `#expect`, `@Suite`). SwiftData-backed tests use `makeInMemoryContext()` (`OpenAppLockTests/TestSupport.swift`); helpers `date(...)` and `utc` are there too.
- **Type/paths (post origin/main merge, PR #26 DTO migration):** the usage payload is `RuleUsageDTO` in `Shared/DTOs/RuleUsageDTO.swift`; `UsageLedger` and `MockUsageLedger` are both in `Shared/Stores/UsageLedger.swift`.
- **No on-device behavior change to enforcement.** The simulator delivers no Screen Time data and does not run DeviceActivityReport extensions; the new report and removed counter are device-only and validated manually.
- **Commits:** conventional (`feat:`/`refactor:`/`test:`…), each ending with a manual trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Work lands via a topic-branch PR for brendan-ch to merge — not direct to `main`. (Branch `chore/fix-time-display` already has `origin/main` merged in.)
- **Spec:** `Docs/Agents/Specs/ACTIVE_RULES_AND_USAGE_REPORT.md`.

## File structure

| File | Responsibility | Tasks |
|---|---|---|
| `OpenAppLock/Logic/UsageDisplay.swift` | Row strings — `usagePhrase` deleted | 1 |
| `OpenAppLock/Logic/RuleStatus.swift` | `rowContext` (no live count) + new `belongsInActiveRules` predicate | 1, 6 |
| `Shared/Platform/UsageReportFormatter.swift` | **New** — pure "Xh Ym today"/blank formatter (Shared, so testable) | 2 |
| `OpenAppLockReport/RuleUsageReport.swift` | Report scene: sum `totalActivityDuration` → render text/blank | 2 |
| `OpenAppLockReport/RuleUsageReportWriter.swift` | **Deleted** (ledger writer removed) | 2 |
| `Shared/Platform/DeviceActivityReportContext.swift` | `.ruleUsage` doc comment | 2 |
| `OpenAppLock/Views/MainView.swift` | Remove invisible report host + `usageFilter` | 3 |
| `Shared/DTOs/RuleSnapshotDTO.swift` | `limitReached` → `minutesUsed` | 4 |
| `OpenAppLock/Services/RuleEnforcer.swift` | Trim `logTimeLimitDecision` | 4 |
| `Shared/DTOs/RuleUsageDTO.swift` | Remove authoritative fields + `effectiveMinutesUsed` | 5 |
| `Shared/Stores/UsageLedger.swift` | Remove `recordAuthoritativeMinutes` | 5 |
| `OpenAppLock/Views/Home/HomeView.swift` | "Usage" → "Active Rules"; tappable rows → detail sheet | 6 |
| `OpenAppLock/Views/Rules/RuleDetailSheet.swift` | Embed per-rule `DeviceActivityReport`; UI-test gate; blank | 7 |
| `OpenAppLockTests/UsageTests.swift` | Delete/adjust display + authoritative tests | 1, 4, 5 |
| `OpenAppLockTests/RuleStatusTests.swift` | Update spent-limit label; add membership test | 1, 6 |
| `OpenAppLockUITests/UsageUITests.swift` | Rewrite for Active Rules | 6 |

---

### Task 1: Drop the live usage count from row strings

**Files:**
- Modify: `OpenAppLock/Logic/RuleStatus.swift` (`rowContext`, lines 77–92)
- Modify: `OpenAppLock/Logic/UsageDisplay.swift` (delete `usagePhrase`, lines 21–33)
- Test: `OpenAppLockTests/UsageTests.swift` (`@Suite("Usage display strings")` — `UsageDisplayTests`)
- Test: `OpenAppLockTests/RuleStatusTests.swift` (`timeLimitBlockingDisplayLabel`)

**Interfaces:**
- Produces: `rowContext(for:usage:relativeTo:)` returns budget for non-blocking limits and `"Blocked until tomorrow"` for a spent (`.active`) limit; `UsageDisplay.usagePhrase` no longer exists.

- [ ] **Step 1: Update the display unit tests to the new strings (RED).**

In `OpenAppLockTests/UsageTests.swift`, inside `@Suite("Usage display strings") struct UsageDisplayTests`:
- **Delete** these `@Test`s (they assert the removed `usagePhrase`): `timeLimitStrings`, `usagePhrasePrefersFreshAuthoritative`, `openLimitStrings`, `overshootClamps`.
- **Replace** `adaptiveLimitContext`, `exhaustedContext`, and `homeSubtitles` with:

```swift
@Test("Limit rows show the daily budget, never a live count")
func limitContextShowsBudget() {
    let idle = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
    #expect(timeRule.dto.rowContext(for: idle, usage: RuleUsageDTO(), relativeTo: now) == "45m / day")

    let used = RuleUsageDTO(minutesUsed: 18) // under budget → still upcoming → budget
    let active = timeRule.dto.status(at: now, calendar: utc, usage: used)
    #expect(timeRule.dto.rowContext(for: active, usage: used, relativeTo: now) == "45m / day")
}

@Test("A spent limit reads 'Blocked until tomorrow'; unblocking it reads Paused")
func spentLimitContext() {
    let spent = RuleUsageDTO(minutesUsed: 45)
    let blocking = timeRule.dto.status(at: now, calendar: utc, usage: spent)
    #expect(blocking.isActive)
    #expect(timeRule.dto.rowContext(for: blocking, usage: spent, relativeTo: now) == "Blocked until tomorrow")

    timeRule.pausedUntil = utc.date(byAdding: .hour, value: 5, to: now)
    let paused = timeRule.dto.status(at: now, calendar: utc, usage: spent)
    #expect(timeRule.dto.rowContext(for: paused, usage: spent, relativeTo: now) == "Paused")
}

@Test("Home subtitles prefix the rule kind")
func homeSubtitles() {
    let timeStatus = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
    #expect(
        UsageDisplay.homeSubtitle(for: timeRule.dto, status: timeStatus, usage: RuleUsageDTO(), relativeTo: now)
            == "Time Limit · 45m / day")

    let openStatus = openRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
    #expect(
        UsageDisplay.homeSubtitle(for: openRule.dto, status: openStatus, usage: RuleUsageDTO(), relativeTo: now)
            == "Open Limit · 5 opens / day")
}
```

In `OpenAppLockTests/RuleStatusTests.swift`, replace `timeLimitBlockingDisplayLabel`'s expectation:

```swift
@Test("A spent time-limit budget reads 'Blocked until tomorrow'")
func timeLimitBlockingDisplayLabel() {
    let rule = BlockingRule(
        name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
    let now = date(2025, 1, 6, 11, 38)
    let usage = RuleUsageDTO(minutesUsed: 15)
    let status = rule.dto.status(at: now, calendar: utc, usage: usage)
    #expect(status.isActive)
    #expect(rule.dto.rowContext(for: status, usage: usage, relativeTo: now) == "Blocked until tomorrow")
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageDisplayTests` and `OpenAppLockTests/RuleStatusTests/timeLimitBlockingDisplayLabel`.
Expected: FAIL/compile error (`rowContext` still returns "18m of 45m used"; `usagePhrase` still referenced where deleted tests were).

- [ ] **Step 3: Rewrite `rowContext` and delete `usagePhrase`.**

In `OpenAppLock/Logic/RuleStatus.swift`, replace the `.timeLimit, .openLimit` arm of `rowContext` (keep the `usage` parameter on the signature — it stays part of the row-renderer interface):

```swift
        case .timeLimit, .openLimit:
            switch status {
            case .disabled, .dormant, .paused:
                return status.label(relativeTo: now)
            case .active:
                // A spent budget blocks for the rest of the day; the detail row
                // ("Then block until: Tomorrow") names the same moment.
                return "Blocked until tomorrow"
            case .upcoming:
                return UsageDisplay.budgetPhrase(for: self)
            }
```

In `OpenAppLock/Logic/UsageDisplay.swift`, delete the entire `usagePhrase(for:usage:asOf:)` function (lines 21–33). Keep `homeSubtitle` and `budgetPhrase`.

- [ ] **Step 4: Run the tests — verify they pass.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageDisplayTests` and `OpenAppLockTests/RuleStatusTests`.
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add OpenAppLock/Logic/RuleStatus.swift OpenAppLock/Logic/UsageDisplay.swift OpenAppLockTests/UsageTests.swift OpenAppLockTests/RuleStatusTests.swift
git commit -m "refactor: drop live usage count from rule-row strings

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Repurpose the report extension to render a per-rule usage total

**Files:**
- Create: `Shared/Platform/UsageReportFormatter.swift`
- Modify: `OpenAppLockReport/RuleUsageReport.swift`
- Delete: `OpenAppLockReport/RuleUsageReportWriter.swift`
- Modify: `Shared/Platform/DeviceActivityReportContext.swift` (doc comment only)
- Test: `OpenAppLockTests/UsageTests.swift` (new `@Suite` for the formatter)

**Interfaces:**
- Produces: `UsageReportFormatter.todayTotal(seconds: Double) -> String` — `"1h 12m today"` / `"22m today"` / `""` (blank when < 1 minute). Consumed by the report scene (Task 2) and indirectly validated in `RuleDetailSheet` (Task 7).

- [ ] **Step 1: Write the formatter test (RED).**

Add to `OpenAppLockTests/UsageTests.swift`:

```swift
@MainActor
@Suite("Usage report formatter")
struct UsageReportFormatterTests {
    @Test("Formats today's total; blank under a minute")
    func formatsTotal() {
        #expect(UsageReportFormatter.todayTotal(seconds: 0) == "")
        #expect(UsageReportFormatter.todayTotal(seconds: 59) == "")
        #expect(UsageReportFormatter.todayTotal(seconds: 60) == "1m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 22 * 60) == "22m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 72 * 60) == "1h 12m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 120 * 60) == "2h today")
    }
}
```

- [ ] **Step 2: Run the test — verify it fails.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageReportFormatterTests`.
Expected: FAIL — "cannot find 'UsageReportFormatter' in scope".

- [ ] **Step 3: Create the formatter.**

Create `Shared/Platform/UsageReportFormatter.swift`:

```swift
//
//  UsageReportFormatter.swift
//  OpenAppLock
//

import Foundation

/// Formats a day's foreground-usage total for the rule-detail report view.
/// Pure and Shared so the report extension can render it and unit tests can
/// cover it. Returns an empty string under one minute — the report's blank state.
enum UsageReportFormatter {
    static func todayTotal(seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        guard minutes > 0 else { return "" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m today" }
        if hours > 0 { return "\(hours)h today" }
        return "\(remainder)m today"
    }
}
```

- [ ] **Step 4: Run the test — verify it passes.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageReportFormatterTests`.
Expected: PASS.

- [ ] **Step 5: Rewrite the report scene to render instead of write; delete the writer.**

Replace `OpenAppLockReport/RuleUsageReport.swift` with:

```swift
//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Renders the filtered rule's combined foreground usage for today. The host
/// (`RuleDetailSheet`) scopes the data via the report's filter, so this scene
/// stays identity-agnostic and never reads the app group. Runs only while the
/// host app foregrounds a `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (String) -> Text = { Text($0) }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> String {
        var seconds = 0.0
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    seconds += app.totalActivityDuration
                }
            }
        }
        return UsageReportFormatter.todayTotal(seconds: seconds)
    }
}
```

Delete `OpenAppLockReport/RuleUsageReportWriter.swift` (the file-system-synchronized group drops it from the target on disk-delete).

Update the doc comment in `Shared/Platform/DeviceActivityReportContext.swift`:

```swift
extension DeviceActivityReport.Context {
    /// The report scene that renders a rule's combined foreground usage for
    /// today. Shared so the host app and the report extension name it the same.
    static let ruleUsage = Self("Rule Usage")
}
```

- [ ] **Step 6: Build — verify the extension compiles and nothing references the deleted writer.**

Run via Xcode MCP `BuildProject`.
Expected: BUILD SUCCEEDED. (`RuleUsageReportWriter` is referenced only by the old scene, now replaced; `MainView` still references `.ruleUsage` — fine, removed in Task 3.)

- [ ] **Step 7: Commit.**

```bash
git add Shared/Platform/UsageReportFormatter.swift OpenAppLockReport/RuleUsageReport.swift Shared/Platform/DeviceActivityReportContext.swift OpenAppLockTests/UsageTests.swift
git rm OpenAppLockReport/RuleUsageReportWriter.swift
git commit -m "feat: render rule usage in the report extension instead of writing the ledger

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Remove the invisible authoritative-report host from MainView

**Files:**
- Modify: `OpenAppLock/Views/MainView.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `MainView` no longer hosts any `DeviceActivityReport`; the extension now runs only from `RuleDetailSheet` (Task 7).

- [ ] **Step 1: Remove the report host and filter.**

In `OpenAppLock/Views/MainView.swift`:
- Delete `.background(ruleUsageReport)` from `body` (the `layout` modifier chain).
- Delete the `ruleUsageReport` computed property and the `usageFilter` computed property (the "Authoritative usage report" MARK section).
- Remove now-unused imports `import DeviceActivity` and `import FamilyControls` (keep `ManagedSettings`, `SwiftData`, `SwiftUI` if still used; the build in Step 2 confirms).

- [ ] **Step 2: Build — verify it compiles.**

Run via Xcode MCP `BuildProject`.
Expected: BUILD SUCCEEDED. If an "unused import" or "unresolved identifier" appears, remove/restore the flagged import accordingly and rebuild.

- [ ] **Step 3: Run the full unit suite — verify still green.**

Run via Xcode MCP `RunAllTests`.
Expected: PASS (no test exercises the invisible host).

- [ ] **Step 4: Commit.**

```bash
git add OpenAppLock/Views/MainView.swift
git commit -m "refactor: drop the invisible authoritative-usage report host

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Make the block decision read the threshold count directly

**Files:**
- Modify: `Shared/DTOs/RuleSnapshotDTO.swift` (`limitReached`, lines 48–53)
- Modify: `OpenAppLock/Services/RuleEnforcer.swift` (`logTimeLimitDecision`, ~lines 152–171)
- Test: `OpenAppLockTests/UsageTests.swift` (delete authoritative-enforcement tests; add a threshold test)

**Interfaces:**
- Produces: `RuleSnapshotDTO.limitReached(given:at:)` uses `usage.minutesUsed >= dailyLimitMinutes` (no `effectiveMinutesUsed`).

- [ ] **Step 1: Replace the authoritative-enforcement tests with a threshold test (RED).**

In `OpenAppLockTests/UsageTests.swift`, **delete** these `@Test`s (they assert the removed authoritative-vs-threshold enforcement): `"A fresh authoritative reading below budget keeps a rule inactive"`, `"A fresh authoritative reading at budget blocks even if threshold lags"`, `"A stale authoritative reading falls back to the threshold count"`, and `freshAuthoritativeClearsPhantomBlock` (`"A fresh authoritative reading below budget clears a phantom block"`).

Add (in the limit-enforcement suite that already builds a `RuleEnforcer` with `MockShieldController`/`MockUsageLedger` — mirror its existing setup):

```swift
@Test("A time limit blocks once the threshold count reaches the budget")
func thresholdReachingBudgetBlocks() {
    let shields = MockShieldController()
    let ledger = MockUsageLedger()
    let enforcer = RuleEnforcer(shields: shields, usage: ledger)
    let rule = BlockingRule(
        name: "Time Keeper",
        configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
        days: Weekday.everyDay)
    ledger.usageByRule[rule.id] = RuleUsageDTO(minutesUsed: 45)

    enforcer.refresh(rules: [rule], at: mondayMorning, calendar: utc)

    #expect(shields.shieldedRuleIDs.contains(rule.id))
}
```

- [ ] **Step 2: Run — verify it fails.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageTests/thresholdReachingBudgetBlocks`.
Expected: PASS already if `effectiveMinutesUsed` falls back to `minutesUsed` — that is fine; this test pins the behavior we are preserving. If it does not yet build because of the deletions, fix the deletions until the suite compiles. The RED signal for this task is the compile error from removing the authoritative tests' references; proceed once they are gone.

- [ ] **Step 3: Change `limitReached` and trim the decision log.**

In `Shared/DTOs/RuleSnapshotDTO.swift`:

```swift
    func limitReached(given usage: RuleUsageDTO, at now: Date = .now) -> Bool {
        switch kind {
        case .schedule: false
        case .timeLimit: usage.minutesUsed >= dailyLimitMinutes
        case .openLimit: usage.opensUsed >= maxOpens
        }
    }
```

In `OpenAppLock/Services/RuleEnforcer.swift`, replace the body of `logTimeLimitDecision(_:usage:isBlocking:at:)` with a threshold-only line (drop `effectiveMinutesUsed`, `authoritativeMinutesUsed`, `authoritativeAsOf`, the `source=`/`auth=` fields, and the EC4 "authoritative lifted a real block" WARN, which can no longer occur):

```swift
    private func logTimeLimitDecision(
        _ rule: BlockingRule, usage: RuleUsageDTO?, isBlocking: Bool, at now: Date
    ) {
        guard rule.kind == .timeLimit, let usage else { return }
        let rid = rule.id.uuidString.prefix(8)
        Diag.log(
            .usage,
            "timeLimit rule-\(rid) used=\(usage.minutesUsed)/\(rule.dailyLimitMinutes) blocking=\(isBlocking)")
    }
```

- [ ] **Step 4: Run the limit/enforcement suites — verify green.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageTests` and `OpenAppLockTests/RuleEnforcerTests`.
Expected: PASS.

- [ ] **Step 5: Commit.**

```bash
git add Shared/DTOs/RuleSnapshotDTO.swift OpenAppLock/Services/RuleEnforcer.swift OpenAppLockTests/UsageTests.swift
git commit -m "refactor: block decision reads the threshold count directly

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Delete the authoritative usage machinery

**Files:**
- Modify: `Shared/DTOs/RuleUsageDTO.swift`
- Modify: `Shared/Stores/UsageLedger.swift`
- Test: `OpenAppLockTests/UsageTests.swift` (delete the remaining authoritative struct/ledger tests)

**Interfaces:**
- Produces: `RuleUsageDTO` is `{ minutesUsed, opensUsed }` only; `UsageLedger` has no `recordAuthoritativeMinutes`.

- [ ] **Step 1: Delete the authoritative struct/ledger tests (RED-by-removal).**

In `OpenAppLockTests/UsageTests.swift`, **delete** these `@Test`s: `"Effective minutes prefer a fresh authoritative reading, else fall back"`, `"Usage round-trips authoritative fields and decodes legacy blobs"` (`authoritativeCodable`), and `recordAuthoritative` (`"…"` test that calls `ledger.recordAuthoritativeMinutes`). If `authoritativeCodable` also covered basic round-trip, add a minimal replacement:

```swift
@Test("RuleUsageDTO round-trips minutes and opens")
func usageCodable() throws {
    let usage = RuleUsageDTO(minutesUsed: 30, opensUsed: 2)
    let data = try JSONEncoder().encode(usage)
    let decoded = try JSONDecoder().decode(RuleUsageDTO.self, from: data)
    #expect(decoded == usage)
}
```

- [ ] **Step 2: Run — verify compile failure points only at the deleted API.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/UsageTests`.
Expected: FAIL/compile error only where remaining code references `authoritativeMinutesUsed` / `effectiveMinutesUsed` / `recordAuthoritativeMinutes` (there should be none in production after Tasks 1–4; the errors should be confined to any test lines still referencing them — remove those too).

- [ ] **Step 3: Strip the authoritative API from the DTO and ledger.**

Replace `Shared/DTOs/RuleUsageDTO.swift` body with:

```swift
//
//  RuleUsageDTO.swift
//  OpenAppLock
//

import Foundation

/// Codable mirror of what a limit rule has consumed on a given day, persisted
/// to the app group by `UsageLedger`. Written by the DeviceActivity monitor
/// (minutes) and shield-action extension (opens); read by the app for display
/// and enforcement.
nonisolated struct RuleUsageDTO: Codable, Equatable {
    var minutesUsed = 0
    var opensUsed = 0
}
```

In `Shared/Stores/UsageLedger.swift`, delete the `recordAuthoritativeMinutes(_:for:onDayContaining:asOf:calendar:)` method (lines 65–75). Leave `recordMinutesUsed`, `recordOpen`, `usage`, `setUsage`, and `MockUsageLedger` intact.

- [ ] **Step 4: Build, then run the full suite — verify green.**

Run via Xcode MCP `BuildProject`, then `RunAllTests`.
Expected: BUILD SUCCEEDED; all tests PASS. (Old stored usage blobs with authoritative keys still decode — `JSONDecoder` ignores unknown keys — so no migration is needed.)

- [ ] **Step 5: Commit.**

```bash
git add Shared/DTOs/RuleUsageDTO.swift Shared/Stores/UsageLedger.swift OpenAppLockTests/UsageTests.swift
git commit -m "refactor: remove the dead authoritative-usage machinery

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Reshape Home into Currently Blocking + Active Rules

**Files:**
- Modify: `OpenAppLock/Logic/RuleStatus.swift` (add `belongsInActiveRules`)
- Modify: `OpenAppLock/Views/Home/HomeView.swift`
- Test: `OpenAppLockTests/RuleStatusTests.swift` (membership predicate)
- Test: `OpenAppLockUITests/UsageUITests.swift` (rewrite)

**Interfaces:**
- Produces: `RuleSnapshotDTO.belongsInActiveRules(at:calendar:usage:) -> Bool`. Home row identifier `activeRuleRow-<name>`; section header `"Active Rules"`.

- [ ] **Step 1: Write the membership-predicate test (RED).**

Add to `OpenAppLockTests/RuleStatusTests.swift`:

```swift
@MainActor
@Suite("Active Rules membership")
struct ActiveRulesMembershipTests {
    let now = date(2025, 1, 6, 10, 0) // Monday 10:00

    @Test("A limit scheduled today and under budget belongs in Active Rules")
    func underBudgetLimitIncluded() {
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        #expect(rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO(minutesUsed: 10)))
    }

    @Test("A spent (blocking) limit is excluded — it belongs in Currently Blocking")
    func spentLimitExcluded() {
        let rule = BlockingRule(
            name: "Doom Scroll",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30)),
            days: Weekday.everyDay)
        #expect(!rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO(minutesUsed: 30)))
    }

    @Test("A schedule starting within 24h is included; beyond 24h is excluded")
    func scheduleWithin24h() {
        // Window 12:00–13:00 today → starts in 2h → included.
        let soon = BlockingRule(
            name: "Soon",
            configuration: .schedule(ScheduleConfig(blockAdultContent: false)),
            startMinutes: 12 * 60, endMinutes: 13 * 60, days: Weekday.everyDay)
        #expect(soon.dto.belongsInActiveRules(at: now, calendar: utc, usage: nil))

        // Window 09:00–10:00, only on Wednesdays → next start > 24h from Monday.
        let later = BlockingRule(
            name: "Later",
            configuration: .schedule(ScheduleConfig(blockAdultContent: false)),
            startMinutes: 9 * 60, endMinutes: 10 * 60, days: [.wednesday])
        #expect(!later.dto.belongsInActiveRules(at: now, calendar: utc, usage: nil))
    }

    @Test("A disabled rule is excluded")
    func disabledExcluded() {
        let rule = BlockingRule(
            name: "Off",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        rule.isEnabled = false
        #expect(!rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO()))
    }
}
```

> Note: verify `ScheduleConfig`'s initializer/label against `Shared/Models/RuleConfiguration.swift` and match how other tests in this suite build schedule rules; adjust the `.schedule(...)` construction to the project's actual API before running.

- [ ] **Step 2: Run — verify it fails.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/ActiveRulesMembershipTests`.
Expected: FAIL — "cannot find 'belongsInActiveRules'".

- [ ] **Step 3: Add the predicate.**

In `OpenAppLock/Logic/RuleStatus.swift`, add to the `extension RuleSnapshotDTO`:

```swift
    /// Whether this rule belongs in Home's "Active Rules" section: enabled and
    /// not currently blocking, and either a limit rule scheduled today or a
    /// schedule rule whose next window starts within the next 24 hours. Rules
    /// blocking now live in "Currently Blocking" instead.
    func belongsInActiveRules(
        at now: Date, calendar: Calendar = .current, usage: RuleUsageDTO?
    ) -> Bool {
        guard isEnabled else { return false }
        let status = status(at: now, calendar: calendar, usage: usage)
        if status.isActive { return false }
        switch kind {
        case .timeLimit, .openLimit:
            return isScheduledToday(at: now, calendar: calendar)
        case .schedule:
            if case .upcoming(let startsAt) = status {
                return startsAt.timeIntervalSince(now) <= 24 * 60 * 60
            }
            return false
        }
    }
```

- [ ] **Step 4: Run the predicate tests — verify they pass.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockTests/ActiveRulesMembershipTests`.
Expected: PASS.

- [ ] **Step 5: Reshape `HomeView` — rename the section, use the predicate, make rows open the detail sheet.**

In `OpenAppLock/Views/Home/HomeView.swift`:
- Add detail-sheet state: `@State private var detailRule: BlockingRule?`.
- Attach `.sheet(item: $detailRule) { RuleDetailSheet(rule: $0) }` to the `NavigationStack` (mirror `RulesListView`).
- Replace `usageSection`'s membership and header:

```swift
    @ViewBuilder
    private func activeRulesSection(now: Date) -> some View {
        let active = rules.filter {
            $0.dto.belongsInActiveRules(at: now, usage: enforcer.usage(for: $0.dto, at: now))
        }
        if !active.isEmpty {
            Section {
                ForEach(active) { rule in
                    activeRuleRow(for: rule, now: now)
                }
            } header: {
                Text("Active Rules").textCase(nil)
            }
        }
    }
```

- Replace `usageRow` with a tappable button (`activeRuleRow`):

```swift
    private func activeRuleRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsageDTO()
        let status = liveStatus(for: rule, now: now)
        return Button {
            detailRule = rule
        } label: {
            HStack {
                kindIcon(for: rule)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).foregroundStyle(Color.primary)
                    Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityIdentifier("activeRuleRow-\(rule.name)")
    }
```

- Update `homeList(now:)` to call `activeRulesSection(now:)` instead of `usageSection(now:)`, and rename/remove the old `usageSection`/`usageRow`. Update the `// MARK: - Usage` comment to `// MARK: - Active Rules`.

- [ ] **Step 6: Rewrite the UI tests for Active Rules.**

Replace `OpenAppLockUITests/UsageUITests.swift` with:

```swift
//
//  UsageUITests.swift
//  OpenAppLockUITests
//

import XCTest

/// The "Active Rules" section on Home — seeded limit rules show their budget,
/// a spent rule moves to Currently Blocking reading "Blocked until tomorrow",
/// and rows open the rule-detail overlay.
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

        let tile = app.buttons["blockedTile-Doom Scroll"].waitToAppear()
        XCTAssertTrue(tile.label.contains("Blocked until tomorrow"), "Got: \(tile.label)")

        XCTAssertFalse(
            app.element("activeRuleRow-Doom Scroll").exists,
            "A spent rule should leave Active Rules for Currently Blocking")
    }

    func testTappingActiveRuleOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        app.element("activeRuleRow-Time Keeper").waitToAppear().tap()
        XCTAssertTrue(app.staticTexts["detailRuleName"].waitToAppear().exists)
        XCTAssertEqual(app.staticTexts["detailRuleName"].label, "Time Keeper")
    }
}
```

> Note: confirm the `limits` seed scenario still seeds "Time Keeper", "Gate Keeper", and a spent "Doom Scroll" (`OpenAppLock/Services/SampleRules.swift`, changed by the merge). Adjust names if the scenario changed.

- [ ] **Step 7: Run the UI tests on a simulator — verify they pass.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockUITests/UsageUITests` (scheme destination = iOS Simulator).
Expected: PASS.

- [ ] **Step 8: Commit.**

```bash
git add OpenAppLock/Logic/RuleStatus.swift OpenAppLock/Views/Home/HomeView.swift OpenAppLockTests/RuleStatusTests.swift OpenAppLockUITests/UsageUITests.swift
git commit -m "feat: rename Home Usage section to Active Rules with tappable rows

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Embed the per-rule DeviceActivityReport in RuleDetailSheet

**Files:**
- Modify: `OpenAppLock/Views/Rules/RuleDetailSheet.swift`

**Interfaces:**
- Consumes: `DeviceActivityReport(.ruleUsage, filter:)` (the scene from Task 2); `AppSelectionCodec.decode`; `LaunchConfiguration.current.isUITesting`.

- [ ] **Step 1: Add the report section, gated and scoped.**

In `OpenAppLock/Views/Rules/RuleDetailSheet.swift`:
- Add imports: `import DeviceActivity` and `import FamilyControls`.
- Add a per-rule filter and a "Usage" section to `detailList(now:)`'s `List` (after the existing facts `Section`), shown for all kinds and gated under UI testing:

```swift
            // Live Screen Time usage for this rule's apps, rendered inside the
            // report extension (the only place the data is available). Gated
            // under UI testing — the system view does not run in the harness —
            // and blank when there is no usage.
            if !LaunchConfiguration.current.isUITesting {
                Section("Usage") {
                    DeviceActivityReport(.ruleUsage, filter: usageFilter)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .accessibilityIdentifier("ruleUsageReport")
                }
            }
```

- Add the filter builder:

```swift
    /// Today's `.daily` filter scoped to this rule's selection, so the report
    /// extension attributes only this rule's apps/categories/web domains.
    private var usageFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let interval = DateInterval(start: calendar.startOfDay(for: .now), end: .now)
        let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens)
    }
```

- [ ] **Step 2: Build — verify it compiles.**

Run via Xcode MCP `BuildProject`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run the rule-detail / usage UI tests — verify still green under the UI-test gate.**

Run via Xcode MCP `RunSomeTests` for `OpenAppLockUITests/UsageUITests` and any `RuleDetail`-touching UI suite.
Expected: PASS (the report section is gated off under `-ui-testing`, so detail flows are unaffected).

- [ ] **Step 4: Manual device validation (tooling permitting).**

On a device with Screen Time authorized: open a limit rule's detail and confirm the "Usage" section renders a plausible "Xh Ym today" for the rule's apps, and renders blank when there is no usage. (Simulator cannot exercise this — if no device is available, record that this step is handed back to the maintainer.)

- [ ] **Step 5: Commit.**

```bash
git add OpenAppLock/Views/Rules/RuleDetailSheet.swift
git commit -m "feat: embed per-rule DeviceActivityReport in the rule detail overlay

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Remove "Xm of Ym" everywhere incl. detail caption → Task 1 (`rowContext`/`usagePhrase`); the `RuleDetailSheet` caption uses `rowContext`, so it is covered transitively.
- Rename Usage→Active Rules, tappable rows, 24h schedule window, all kinds → Task 6.
- Per-rule `DeviceActivityReport` rendering today's total, blank state → Tasks 2 + 7.
- Full authoritative-path removal (`MainView` host, writer, ledger fields, `limitReached`) → Tasks 3, 2, 5, 4.
- UI-testing gate + test fallout → Tasks 6, 7 + deletions across Tasks 1, 4, 5.

**Placeholder scan:** No "TBD"/"add error handling"/"similar to". Two explicit "verify against the actual API" notes (ScheduleConfig construction in Task 6 Step 1; `limits` seed names in Task 6 Step 6) are deliberate guardrails because the merge touched `SampleRules.swift`/`RuleConfiguration.swift` — the implementer confirms the exact initializer before running. Manual device validation (Task 7 Step 4) is inherent to a device-only feature.

**Type consistency:** `RuleUsageDTO` used throughout (post-merge). `belongsInActiveRules(at:calendar:usage:)`, `UsageReportFormatter.todayTotal(seconds:)`, `rowContext(for:usage:relativeTo:)`, and the `.ruleUsage` context name match between defining and consuming tasks. The `usage` parameter is intentionally retained on `rowContext`/`homeSubtitle` even though the new branches don't read it (no Swift unused-parameter warning).

**Ordering invariant:** each task ends with a green build/suite — display strings (1) before deleting `usagePhrase`; the report scene (2) drops the `recordAuthoritativeMinutes` call before the method is deleted (5); `limitReached` (4) drops the last `effectiveMinutesUsed` consumer before the DTO field is deleted (5).
