# Rule Status-Label Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Project note:** the flow-gate clamp requires an allowed flow to be active before editing code — this change maps to `spec-driven-development` (implementing a committed spec); ensure it (or an equivalent gate-unlocking flow) is invoked before the first code edit.

**Goal:** Make every rule's one-line status label read as a live countdown to its next transition — limit rules read "Resets in {countdown}" (or "Starts in {countdown}" when not scheduled today), and schedule rules read "Ends in {countdown}" instead of "{countdown} left".

**Architecture:** All four render sites (Home "Currently Blocking", Home "Active Rules", the Rules tab row, and the rule-detail Status row) share a single string producer, `RuleSnapshotDTO.rowContext(for:usage:relativeTo:)` in `OpenAppLock/Logic/RuleStatus.swift`. The change is made once there (plus one catalog value relabel that the shared `RuleStatus.label` already reads), so wording stays uniform across sites by construction. Copy lives in `Shared/Copy.xcstrings` keyed by `CopyKey` cases; no view code changes.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, iOS 26; Xcode String Catalog (`Shared/Copy.xcstrings`, its own `Copy` table) with `CopyKey`; Swift Testing (unit) + XCTest/XCUITest (UI). Build & test through the **Xcode MCP** tools only.

## Global Constraints

- Single source of truth: change only `RuleSnapshotDTO.rowContext(...)` — **no per-render-site divergence** (spec §2, §5). The four render sites all consume `rowContext`; do not special-case any site (hiding the detail Status row was tried and reverted, `f6dbd2f`/`a614faa`).
- Limit rules **scheduled today**: "Resets in {countdown to tonight's midnight}" — identical whether the budget is spent (blocking) or still available (spec §4, §5).
- Limit rules **not scheduled today**: "Starts in {countdown to the next enabled day}" via the existing upcoming label (spec §4).
- Selection between the two limit cases is keyed off `RuleSnapshotDTO.isScheduledToday(at:)`, **not** the `.active` / `.upcoming` distinction (spec §4).
- Compute the reset moment via `calendar.nextMidnight(after: now)` **fresh** — never reuse the upcoming `startsAt` for "Resets in" (spec §3, §4).
- Schedule Active relabel: "{countdown} left" → "Ends in {countdown}" is a catalog **value** change on `status.activeLeft` only; the `statusActiveLeft` case name stays, so `RuleStatus.label` needs no Swift change (spec §4, §8).
- Disabled / No days selected / Paused wording is unchanged for both kinds (shared `RuleStatus.label`) (spec §4).
- Budget-at-a-glance ("45m / day", "5 opens / day") is removed everywhere `rowContext` renders; no budget-amount display remains (spec §6).
- Non-goal: the detail sheet's "Then block until: Tomorrow" row is left exactly as-is — do **not** touch it (spec §7).
- New key `status.resetsIn` = "Resets in %@" mirrors `status.startsIn`; consumed with `RuleStatus.countdown(from:to:)` as the `%@` arg (spec §8).
- Remove dead symbols once uncalled: `UsageDisplay.budgetPhrase(for:)`, `CopyKey.statusBlockedUntilTomorrow`, `CopyKey.statusRunning`, `CopyKey.usageMinutesPerDay`, `CopyKey.usageOpensPerDay` (+ their `Shared/Copy.xcstrings` entries) (spec §8).
- Copy conventions: one catalog `Shared/Copy.xcstrings` (its own `Copy` table), every entry `"extractionState": "manual"` with an `en` `stringUnit`, symbolic dotted keys, smart typography, `%@`/`%lld` placeholders.
- Build/test via **Xcode MCP** only: `BuildProject` (with `buildForTesting: true`), then `RunSomeTests` with `{targetName, testIdentifier}` pairs, or `RunAllTests`; scheme destination must be an iOS **simulator**. Fallback only if MCP is unavailable: `xcodebuild test -only-testing:<target>/<TestClass>/<testMethod>`.
- Tests: `OpenAppLockTests/` uses Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `@MainActor`); `OpenAppLockUITests/` uses XCTest/XCUITest with the `UITestSupport` helpers (`element(_:)`, `waitToAppear()`, `waitForLabel(containing:)`).
- Conventional commits; every commit ends with a `Co-Authored-By:` trailer naming the executing agent/model.
- **Uncommitted-WIP baseline (not a clean HEAD):** the tree already contains an abandoned "Running" placeholder in `rowContext` plus matching test edits (`RuleStatus.swift`, `RuleStatusTests.swift`, `UsageTests.swift`, `CopyKey.swift`, `Copy.xcstrings`). This plan **supersedes** that WIP (spec §3, §8); Tasks 1–2 rewrite those exact spots rather than starting from a clean baseline. Do not `git checkout`/discard the WIP first — edit it into the target state so the diff stays reviewable.

---

### Task 1: String Catalog + `CopyKey` — add `status.resetsIn`, relabel `status.activeLeft`

Add the new "Resets in %@" key and change the schedule-active value from "%@ left" to "Ends in %@". The relabel flips the schedule-active copy immediately (the shared `RuleStatus.label` reads `status.activeLeft` with no Swift change), so this task also updates the two tests that assert that copy. No dead keys are removed yet — they are still referenced by the WIP `rowContext` and by `budgetPhrase` until Tasks 2–3.

**Files:**
- Modify: `Shared/Copy/CopyKey.swift:198` (insert `statusResetsIn` after `statusStartsIn`)
- Modify: `Shared/Copy.xcstrings` (change `status.activeLeft` value at ~`:2083`; add `status.resetsIn` entry near the other `status.*` entries, e.g. before `status.resumesIn` at ~`:2160`)
- Test: `OpenAppLockTests/RuleStatusTests.swift:75-80` (`activeLabel`)
- Test: `OpenAppLockUITests/RuleManagementUITests.swift:27` (`testDetailShowsLiveStatusAndFacts`)

**Interfaces:**
- Consumes: existing `CopyKey` infrastructure — `var string`, `func string(_ args: CVarArg...)`, `LocalizedStringResource resource`.
- Produces:
  - `CopyKey.statusResetsIn` (raw `"status.resetsIn"`) → catalog value `"Resets in %@"`.
  - Relabeled catalog value: `status.activeLeft` → `"Ends in %@"` (case name `statusActiveLeft` unchanged), consumed by the existing `RuleStatus.label(relativeTo:)` `.active` case in `OpenAppLock/Logic/RuleStatus.swift:31`.

- [ ] **Step 1: Update the schedule-active unit test to the new copy (RED)**

In `OpenAppLockTests/RuleStatusTests.swift`, replace the `activeLabel` test (lines 75-80):

```swift
    @Test("Active label rounds hours up")
    func activeLabel() {
        // 11:28 → 17:00 is 5h32m; rounds up to "Ends in 6h".
        let status = workTime().dto.status(at: date(2025, 1, 6, 11, 28), calendar: utc)
        #expect(status.label(relativeTo: date(2025, 1, 6, 11, 28)) == "Ends in 6h")
    }
```

- [ ] **Step 2: Update the detail-sheet UI assertion to the new copy (RED)**

In `OpenAppLockUITests/RuleManagementUITests.swift:27`, change the Status-row assertion inside `testDetailShowsLiveStatusAndFacts`:

```swift
        // before
        XCTAssertTrue(status.label.contains("left"), "Got: \(status.label)")
        // after
        XCTAssertTrue(status.label.contains("Ends in"), "Got: \(status.label)")
```

- [ ] **Step 3: Run the unit test to verify it fails**

Xcode MCP `RunSomeTests`, targetName `OpenAppLockTests`, testIdentifier `RuleStatusTests/activeLabel`.
Expected: FAIL — code still emits "6h left", assertion now wants "Ends in 6h". (The UI test in Step 2 would likewise fail; it is verified GREEN in Step 6 after the catalog change.)

- [ ] **Step 4: Add the `statusResetsIn` case to `CopyKey`**

In `Shared/Copy/CopyKey.swift`, in the `// MARK: - RuleStatus (Task 6)` block, insert the new case immediately after `statusStartsIn` (line 198):

```swift
    case statusStartsIn = "status.startsIn"
    case statusResetsIn = "status.resetsIn"
    case statusCountdownMinutes = "status.countdownMinutes"
```

- [ ] **Step 5: Relabel `status.activeLeft` and add `status.resetsIn` in the catalog**

In `Shared/Copy.xcstrings`, change the `status.activeLeft` value from `"%@ left"` to `"Ends in %@"`:

```json
    "status.activeLeft" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ends in %@"
          }
        }
      }
    },
```

Add the new `status.resetsIn` entry (place it among the other `status.*` entries, e.g. directly before `"status.resumesIn"`):

```json
    "status.resetsIn" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Resets in %@"
          }
        }
      }
    },
```

- [ ] **Step 6: Build, run unit + guardrail tests to verify GREEN**

Xcode MCP `BuildProject` (simulator destination, `buildForTesting: true`) → expect success.
`RunSomeTests`, targetName `OpenAppLockTests`, testIdentifiers `RuleStatusTests/activeLabel` and `CopyCatalogTests/everyKeyResolvesToACatalogValue` and `CopyCatalogTests/everyValueUsesSmartTypography`.
Expected: PASS — `activeLabel` now reads "Ends in 6h"; the guardrail confirms `status.resetsIn` resolves and carries smart typography.

- [ ] **Step 7: Run the detail-sheet UI test to verify GREEN**

`RunSomeTests`, targetName `OpenAppLockUITests`, testIdentifier `RuleManagementUITests/testDetailShowsLiveStatusAndFacts`.
Expected: PASS — the seeded active "Work Time" schedule rule's Status row now reads "Ends in …".

- [ ] **Step 8: Commit**

```bash
git add Shared/Copy/CopyKey.swift Shared/Copy.xcstrings \
        OpenAppLockTests/RuleStatusTests.swift OpenAppLockUITests/RuleManagementUITests.swift
git commit -m "feat: add status.resetsIn key and relabel schedule-active copy to 'Ends in'

Co-Authored-By: <agent/model> <email>"
```

---

### Task 2: Rewrite the limit-rule branch of `rowContext` (+ doc, + calendar threading)

Replace the `.active` / `.upcoming` cases of the `.timeLimit, .openLimit` branch with a single `isScheduledToday`-keyed check, rewrite the stale doc comment to match spec §4, and thread a `calendar` parameter (defaulted to `.current`) through `rowContext` and `UsageDisplay.homeSubtitle` so the midnight computation is deterministic in tests. This is where the WIP "Running"/"Blocked until tomorrow" behavior is superseded.

**Files:**
- Modify: `OpenAppLock/Logic/RuleStatus.swift:66-91` (doc comment + `rowContext` body + signature)
- Modify: `OpenAppLock/Logic/UsageDisplay.swift:10-20` (`homeSubtitle` signature + doc + forward `calendar`)
- Test: `OpenAppLockTests/RuleStatusTests.swift:116-153` (`timeLimitDisplayLabel`, `openLimitDisplayLabel`, `timeLimitBlockingDisplayLabel`; add one new not-scheduled-today test)
- Test: `OpenAppLockTests/UsageTests.swift:235-268` (`limitContextShowsBudget` → rename, `spentLimitContext`, `homeSubtitles`)
- Test: `OpenAppLockUITests/UsageUITests.swift:8-41` (class doc, `testActiveRulesShowBudgets` → rename, `testSpentBudgetMovesToCurrentlyBlocking`)

**Interfaces:**
- Consumes:
  - `CopyKey.statusResetsIn` (Task 1).
  - `RuleSnapshotDTO.isScheduledToday(at: Date, calendar: Calendar) -> Bool` (`Shared/DTOs/RuleSnapshotDTO.swift:39`).
  - `Calendar.nextMidnight(after: Date) -> Date?` (`Shared/Models/Calendar+NextMidnight.swift:11`).
  - `RuleStatus.countdown(from: Date, to: Date) -> String` (`RuleStatus.swift:38`) and `RuleStatus.label(relativeTo: Date)` (`RuleStatus.swift:26`).
- Produces (new signatures other tasks/sites rely on — production call sites keep working via the defaulted `calendar`):
  - `func rowContext(for status: RuleStatus, usage: RuleUsageDTO, relativeTo now: Date, calendar: Calendar = .current) -> String`
  - `static func homeSubtitle(for snapshot: RuleSnapshotDTO, status: RuleStatus, usage: RuleUsageDTO, relativeTo now: Date, calendar: Calendar = .current) -> String`

- [ ] **Step 1: Rewrite the limit-rule unit tests to expect the reset countdown (RED)**

In `OpenAppLockTests/RuleStatusTests.swift`, replace the three kind-aware limit tests (lines 116-153). `date(2025, 1, 6, …)` is a Monday, `Weekday.weekdays` (the `BlockingRule` default) includes Monday, so these limit rules are scheduled today; `utc` next-midnight from 11:38 is 12h22m out → "13h":

```swift
    /// A limit rule scheduled today reads a countdown to tonight's midnight, when
    /// its daily budget resets — not the vestigial 09:00 window start.
    @Test("Scheduled-today time-limit rule shows the reset countdown")
    func timeLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38) // Monday — a scheduled weekday
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(
            rule.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Resets in 13h")
    }

    @Test("Scheduled-today open-limit rule shows the reset countdown")
    func openLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Gate Keeper", configuration: .openLimit(OpenLimitConfig(maxOpens: 5)))
        let now = date(2025, 1, 6, 11, 38)
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(
            rule.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Resets in 13h")
    }

    @Test("Schedule rule still shows the clock countdown")
    func scheduleDisplayLabelUnchanged() {
        let weekend = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)
        let friday = date(2025, 1, 10, 11, 28)
        let status = weekend.dto.status(at: friday, calendar: utc)
        #expect(
            weekend.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: friday, calendar: utc)
                == "Starts in 22h")
    }

    /// A limit rule reads the same "Resets in" countdown whether the budget is
    /// spent (blocking) or still available — both reset at tonight's midnight.
    @Test("A spent time-limit budget reads 'Resets in {countdown}'")
    func timeLimitBlockingDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38)
        let usage = RuleUsageDTO(minutesUsed: 15)
        let status = rule.dto.status(at: now, calendar: utc, usage: usage)
        #expect(status.isActive)
        #expect(
            rule.dto.rowContext(for: status, usage: usage, relativeTo: now, calendar: utc)
                == "Resets in 13h")
    }

    /// A limit rule on a day it is NOT scheduled has no budget to reset today, so
    /// it falls back to the upcoming "Starts in" countdown to its next enabled day.
    @Test("Not-scheduled-today limit rule shows the upcoming Starts-in countdown")
    func limitNotScheduledTodayShowsStartsIn() {
        let rule = BlockingRule(
            name: "Weekend Limit",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30)),
            days: Weekday.weekends)
        let now = date(2025, 1, 6, 11, 38) // Monday — not a scheduled weekend day
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(!rule.dto.isScheduledToday(at: now, calendar: utc))
        #expect(
            rule.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == status.label(relativeTo: now))
        #expect(status.label(relativeTo: now).hasPrefix("Starts in "))
    }
```

(The unchanged `scheduleDisplayLabelUnchanged` test is shown here only because it sits between the edited tests and gains a `calendar: utc` argument for signature consistency; its expected value is unchanged.)

- [ ] **Step 2: Rewrite the `UsageDisplayTests` limit expectations (RED)**

In `OpenAppLockTests/UsageTests.swift`, replace the three tests at lines 235-268. `UsageDisplayTests.now` is `date(2025, 1, 6, 10, 0)` (Monday); `utc` next-midnight from 10:00 is exactly 14h out → "14h":

```swift
    @Test("Scheduled-today limit rows show the reset countdown, spent or not")
    func limitContextShowsResetCountdown() {
        let idle = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            timeRule.dto.rowContext(for: idle, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Resets in 14h")

        let used = RuleUsageDTO(minutesUsed: 18) // under budget → still resets tonight
        let active = timeRule.dto.status(at: now, calendar: utc, usage: used)
        #expect(
            timeRule.dto.rowContext(for: active, usage: used, relativeTo: now, calendar: utc)
                == "Resets in 14h")
    }

    @Test("A spent limit reads 'Resets in {countdown}'; pausing it reads a resume countdown")
    func spentLimitContext() {
        let spent = RuleUsageDTO(minutesUsed: 45)
        let blocking = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(blocking.isActive)
        #expect(
            timeRule.dto.rowContext(for: blocking, usage: spent, relativeTo: now, calendar: utc)
                == "Resets in 14h")

        timeRule.pausedUntil = utc.date(byAdding: .hour, value: 5, to: now)
        let paused = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(
            timeRule.dto.rowContext(for: paused, usage: spent, relativeTo: now, calendar: utc)
                == "Resumes in 5h")
    }

    @Test("Home subtitles prefix the rule kind")
    func homeSubtitles() {
        let timeStatus = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(
                for: timeRule.dto, status: timeStatus, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Time Limit · Resets in 14h")

        let openStatus = openRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(
                for: openRule.dto, status: openStatus, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Open Limit · Resets in 14h")
    }
```

(The `·` in the expected strings is U+00B7, the value of `usage.subtitleSeparator` = "%@ · %@".)

- [ ] **Step 3: Run the unit suites to verify they fail**

Xcode MCP `RunSomeTests`, targetName `OpenAppLockTests`, testIdentifiers `RuleStatusTests` and `UsageDisplayTests`.
Expected: FAIL — the WIP `rowContext` still returns "Running"/"Blocked until tomorrow", and the new tests pass a `calendar:` argument the current signature does not accept (compile error until Step 4). This confirms RED.

- [ ] **Step 4: Rewrite `rowContext` (doc + body + signature)**

In `OpenAppLock/Logic/RuleStatus.swift`, replace the doc comment and function (lines 66-91) with:

```swift
    /// The live "context" line shown under a rule's name on the Home and Rules
    /// lists, and as the rule-detail Status row. A single source of truth so every
    /// screen renders a given kind/state the same way.
    ///
    /// - Schedule rules read their clock status: "Ends in 6h", "Starts in 22h",
    ///   "Resumes in 12m", "Disabled", "No days selected".
    /// - Limit rules (time/open) share that wording while disabled / dormant /
    ///   paused. On a day they are scheduled — whether the budget is spent
    ///   (blocking) or still available — they read "Resets in {countdown}" to
    ///   tonight's midnight, when the daily budget resets. On a day they are not
    ///   scheduled they read the upcoming "Starts in {countdown}" to the next
    ///   enabled day. `isScheduledToday` (not the active/upcoming distinction)
    ///   picks between the two, because a limit rule is only ever `.active` on a
    ///   day it is already scheduled.
    func rowContext(
        for status: RuleStatus, usage: RuleUsageDTO, relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String {
        switch kind {
        case .schedule:
            return status.label(relativeTo: now)
        case .timeLimit, .openLimit:
            switch status {
            case .disabled, .dormant, .paused:
                return status.label(relativeTo: now)
            case .active, .upcoming:
                guard isScheduledToday(at: now, calendar: calendar),
                      let reset = calendar.nextMidnight(after: now)
                else {
                    return status.label(relativeTo: now)
                }
                return CopyKey.statusResetsIn.string(RuleStatus.countdown(from: now, to: reset))
            }
        }
    }
```

- [ ] **Step 5: Thread `calendar` through `homeSubtitle`**

In `OpenAppLock/Logic/UsageDisplay.swift`, replace the `homeSubtitle` doc comment and function (lines 10-20) with:

```swift
    /// The Home-list subtitle: the rule's type, then its live context, so the
    /// kind reads without relying on the icon ("Time Limit · Resets in 8h",
    /// "Schedule · Ends in 6h"). The Rules list omits the type prefix because its
    /// section header already conveys it.
    static func homeSubtitle(
        for snapshot: RuleSnapshotDTO, status: RuleStatus, usage: RuleUsageDTO,
        relativeTo now: Date, calendar: Calendar = .current
    ) -> String {
        CopyKey.usageSubtitleSeparator.string(
            snapshot.kind.displayName,
            snapshot.rowContext(for: status, usage: usage, relativeTo: now, calendar: calendar))
    }
```

(`budgetPhrase(for:)` below it is left untouched here; it is deleted in Task 3. The production call sites — `HomeView.swift:81`, `HomeView.swift:134`, `RulesListView.swift:101`, `RuleDetailSheet.swift:354` — call these without a `calendar:` argument and keep compiling via the `.current` default; do not modify them.)

- [ ] **Step 6: Build, run the unit suites to verify GREEN**

Xcode MCP `BuildProject` → expect success.
`RunSomeTests`, targetName `OpenAppLockTests`, testIdentifiers `RuleStatusTests`, `UsageDisplayTests`, and `CopyCatalogTests`.
Expected: PASS — limit rows now read "Resets in 13h"/"14h", the not-scheduled test delegates to "Starts in …", and the guardrail is still green (`status.resetsIn` resolves; `status.running`/`status.blockedUntilTomorrow` are now unreferenced by code but still carry catalog entries, so nothing dangles).

- [ ] **Step 7: Update the `UsageUITests` copy assertions and class doc (RED → GREEN)**

In `OpenAppLockUITests/UsageUITests.swift`, replace the class doc comment (lines 8-10):

```swift
/// The "Active Rules" section on Home — seeded limit rules show a countdown to
/// tonight's budget reset ("Resets in …"), a spent rule moves to Currently
/// Blocking reading the same reset countdown, and rows open the rule-detail
/// overlay.
```

Rename and rewrite `testActiveRulesShowBudgets` (lines 16-28) — the row still renders, so keep coverage of the kind prefix and assert the new reset copy instead of the dropped budget phrase:

```swift
    func testActiveRulesShowResetCountdown() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        XCTAssertTrue(app.staticTexts["Active Rules"].waitToAppear().exists)

        let timeRow = app.element("activeRuleRow-Time Keeper").waitToAppear()
        XCTAssertTrue(timeRow.label.contains("Time Limit"), "Got: \(timeRow.label)")
        XCTAssertTrue(timeRow.label.contains("Resets in"), "Got: \(timeRow.label)")

        let openRow = app.element("activeRuleRow-Gate Keeper").waitToAppear()
        XCTAssertTrue(openRow.label.contains("Open Limit"), "Got: \(openRow.label)")
        XCTAssertTrue(openRow.label.contains("Resets in"), "Got: \(openRow.label)")
    }
```

Rewrite `testSpentBudgetMovesToCurrentlyBlocking` (lines 30-41):

```swift
    func testSpentBudgetMovesToCurrentlyBlocking() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        // A spent budget is a real block: the rule moves out of Active Rules and
        // into Currently Blocking, reading its reset countdown ("Resets in …").
        let tile = app.buttons["blockedTile-Doom Scroll"].waitToAppear()
        XCTAssertTrue(tile.label.contains("Resets in"), "Got: \(tile.label)")

        XCTAssertFalse(
            app.element("activeRuleRow-Doom Scroll").exists,
            "A spent rule should leave Active Rules for Currently Blocking")
    }
```

- [ ] **Step 8: Run the UI tests to verify GREEN**

`RunSomeTests`, targetName `OpenAppLockUITests`, testIdentifiers `UsageUITests/testActiveRulesShowResetCountdown` and `UsageUITests/testSpentBudgetMovesToCurrentlyBlocking`.
Expected: PASS — the seeded "limits" scenario (every-day limit rules) shows "Resets in …" in both Active Rules and Currently Blocking.

- [ ] **Step 9: Commit**

```bash
git add OpenAppLock/Logic/RuleStatus.swift OpenAppLock/Logic/UsageDisplay.swift \
        OpenAppLockTests/RuleStatusTests.swift OpenAppLockTests/UsageTests.swift \
        OpenAppLockUITests/UsageUITests.swift
git commit -m "feat: render limit-rule status as a reset/starts countdown via isScheduledToday

Co-Authored-By: <agent/model> <email>"
```

---

### Task 3: Remove the now-dead code and catalog entries

With `rowContext` rewritten (Task 2) and `budgetPhrase` already callerless, delete the vestigial producer and the four keys the redesign orphaned. `CopyCatalogTests` is the safety net: it iterates `CopyKey.allCases`, so removing a `case` and its catalog entry together keeps it green, and a build failure would catch any remaining Swift reference.

**Files:**
- Modify: `OpenAppLock/Logic/UsageDisplay.swift:8-9, :22-33` (enum doc + delete `budgetPhrase`)
- Modify: `Shared/Copy/CopyKey.swift:202-203, :206-207` (remove four cases)
- Modify: `Shared/Copy.xcstrings` (remove four entries: `status.blockedUntilTomorrow`, `status.running`, `usage.minutesPerDay`, `usage.opensPerDay`)

**Interfaces:**
- Consumes: nothing new. Relies on Task 2 having removed the last Swift references to `CopyKey.statusBlockedUntilTomorrow` and `CopyKey.statusRunning`, and on `budgetPhrase` being the sole referencer of `CopyKey.usageMinutesPerDay` / `CopyKey.usageOpensPerDay`.
- Produces: no new symbols (removal only). `CopyKey.usageSubtitleSeparator` is **kept** (still used by `homeSubtitle`).

- [ ] **Step 1: Confirm the symbols are dead before removing**

Run these greps; each removed symbol must have **no** remaining reference outside its own declaration:

```bash
grep -rn "budgetPhrase" --include="*.swift" . | grep -v Build
grep -rn "statusBlockedUntilTomorrow\|statusRunning" --include="*.swift" . | grep -v Build
grep -rn "usageMinutesPerDay\|usageOpensPerDay" --include="*.swift" . | grep -v Build
```

Expected: `budgetPhrase` appears only at its definition in `UsageDisplay.swift`; the `status*`/`usage*` symbols appear only at their `CopyKey.swift` case declarations. (The unrelated `minutesPerDay` private constants in `RuleSchedule.swift` and `ScheduleStartNotificationPlan.swift` are different identifiers — leave them.)

- [ ] **Step 2: Delete `budgetPhrase` and simplify the enum doc**

In `OpenAppLock/Logic/UsageDisplay.swift`, replace the enum doc comment (lines 8-9):

```swift
// before
/// Strings for the home- and rules-list rows. Used values clamp to the budget
/// so overshoot (thresholds can fire late) never reads "50m of 45m".
enum UsageDisplay {
// after
/// Strings for the home- and rules-list rows.
enum UsageDisplay {
```

Delete the entire `budgetPhrase(for:)` function (lines 22-33, including its doc comment):

```swift
    /// "45m / day" / "5 opens / day" — the plain daily allowance, shown while a
    /// limit rule has no usage recorded today. Empty for schedule rules.
    static func budgetPhrase(for snapshot: RuleSnapshotDTO) -> String {
        switch snapshot.kind {
        case .schedule:
            ""
        case .timeLimit:
            CopyKey.usageMinutesPerDay.string(snapshot.dailyLimitMinutes)
        case .openLimit:
            CopyKey.usageOpensPerDay.string(snapshot.maxOpens)
        }
    }
```

After this, `UsageDisplay` contains only `homeSubtitle`.

- [ ] **Step 3: Remove the four dead `CopyKey` cases**

In `Shared/Copy/CopyKey.swift`, delete the `statusBlockedUntilTomorrow` and `statusRunning` cases (lines 202-203):

```swift
// before
    case statusCountdownDays = "status.countdownDays"
    case statusBlockedUntilTomorrow = "status.blockedUntilTomorrow"
    case statusRunning = "status.running"

    // MARK: - UsageDisplay (Task 6)
// after
    case statusCountdownDays = "status.countdownDays"

    // MARK: - UsageDisplay (Task 6)
```

Delete the `usageMinutesPerDay` and `usageOpensPerDay` cases (lines 206-207), keeping `usageSubtitleSeparator`:

```swift
// before
    // MARK: - UsageDisplay (Task 6)
    case usageMinutesPerDay = "usage.minutesPerDay"
    case usageOpensPerDay = "usage.opensPerDay"
    case usageSubtitleSeparator = "usage.subtitleSeparator"
// after
    // MARK: - UsageDisplay (Task 6)
    case usageSubtitleSeparator = "usage.subtitleSeparator"
```

- [ ] **Step 4: Remove the four catalog entries**

In `Shared/Copy.xcstrings`, delete these four top-level entries in full (each is a `"key" : { "extractionState" … }` block):

```json
    "status.blockedUntilTomorrow" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Blocked until tomorrow" } }
      }
    },
    "status.running" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Running" } }
      }
    },
    "usage.minutesPerDay" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "%lldm / day" } }
      }
    },
    "usage.opensPerDay" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "%lld opens / day" } }
      }
    },
```

(The entries are pretty-printed across multiple lines in the file; delete the whole JSON object for each of the four keys. Keep the surrounding entries and trailing-comma validity intact.)

- [ ] **Step 5: Build and run the guardrail + touched suites to verify GREEN**

Xcode MCP `BuildProject` → expect success (no dangling references — proves Step 1's greps were complete).
`RunSomeTests`, targetName `OpenAppLockTests`, testIdentifiers `CopyCatalogTests`, `RuleStatusTests`, `UsageDisplayTests`.
Expected: PASS — `CopyCatalogTests/everyKeyResolvesToACatalogValue` confirms no `CopyKey` case lost its entry and no entry was left referenced by a removed case.

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Logic/UsageDisplay.swift Shared/Copy/CopyKey.swift Shared/Copy.xcstrings
git commit -m "chore: remove dead budgetPhrase and orphaned status/usage copy keys

Co-Authored-By: <agent/model> <email>"
```

---

### Task 4: Refresh `AGENTS.md`

Update the one place in `AGENTS.md` that quotes the old schedule-active label, and point the "Derived status & countdown labels" feature-map row at the committed design spec (spec §8). Docs-only; no code or tests change.

**Files:**
- Modify: `AGENTS.md:104` (Domain-facts example)
- Modify: `AGENTS.md:142` (feature-map row)

**Interfaces:**
- Consumes/Produces: none (documentation).

- [ ] **Step 1: Update the countdown-label example**

In `AGENTS.md`, change the Domain-facts bullet at line 104:

```
// before
  Countdown labels round hours **up** (e.g. "6h left").
// after
  Countdown labels round hours **up** (e.g. "Ends in 6h" for a schedule rule,
  "Resets in 8h" for a limit rule).
```

- [ ] **Step 2: Reference the design spec from the feature map**

In `AGENTS.md`, extend the "Derived status & countdown labels" row (line 142):

```
// before
| Derived status & countdown labels | `OpenAppLock/Logic/RuleStatus.swift` |
// after
| Derived status & countdown labels (row-context copy per kind/state) | `OpenAppLock/Logic/RuleStatus.swift`, `OpenAppLock/Logic/UsageDisplay.swift`; design spec `Docs/Agents/Specs/RULE_STATUS_LABEL_REDESIGN.md` |
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: refresh status-label wording and feature map for the redesign

Co-Authored-By: <agent/model> <email>"
```

---

### Final verification (before opening a PR)

- [ ] **Full suite:** Xcode MCP `RunAllTests` on a simulator → expect PASS across unit + UI (iPhone and iPad matrix). Re-run any known-flaky suites in isolation before treating a failure as a regression (e.g. `RuleSchedulerTests`, `NotificationSettingsUITests`, and pause UI tests that flake near midnight).
- [ ] **Manual UI spot-check (optional):** `RunProject` on a simulator with `-seed-scenario=limits`; confirm Active Rules rows and the Currently Blocking tile read "Resets in …", and a seeded active schedule rule ("standard" scenario) reads "Ends in …". If MCP/simulator is unavailable, say so and hand this to the maintainer.
- [ ] **PR:** push the branch (`feat/conditional-status-row-time-limit`) and open a PR summarizing the copy change + test plan; include the "Generated with Claude Code" footer. Do not merge — the maintainer reviews.

---

## Self-Review

**Spec coverage (section by section):**
- §1 Motivation / §2 Scope (one function, four sites, no per-site divergence) → Task 2 rewrites `rowContext`; Global Constraints forbid site special-casing; call sites explicitly left unchanged (Task 2 Step 5).
- §3 Current behavior / WIP starting point → Global Constraints "Uncommitted-WIP baseline"; Tasks 1–2 edit the exact WIP spots (Running placeholder + WIP test edits) rather than a clean HEAD.
- §4 New behavior — copy table & logic → Task 1 (schedule "Ends in", `status.resetsIn` key) + Task 2 (`isScheduledToday`-keyed branch, `nextMidnight`, fallback to upcoming "Starts in"). Disabled/dormant/paused shared path preserved in the rewritten body.
- §5 Rationale (uniform change; unified "Resets in"; keep Paused countdown) → encoded in Task 2 body + tests (`spentLimitContext` keeps "Resumes in 5h"; spent and unspent both "Resets in 14h").
- §6 Budget-at-a-glance removed → Task 3 deletes `budgetPhrase`; Task 2 UI test drops the "45m / day" / "5 opens / day" assertions.
- §7 Non-goal ("Then block until: Tomorrow" left as-is) → Global Constraints + no task touches `RuleDetailSheet.detailRows`.
- §8 Implementation notes (new key; value-only relabel; dead-code list; doc updates) → Task 1 (key + relabel), Task 3 (all four removals), Task 2 (`rowContext` doc rewrite) + Task 4 (`AGENTS.md`).

**Placeholder scan:** No "TBD"/"add error handling"/"similar to Task N". Every code step shows complete Swift/JSON. The only intentional fill-in is `Co-Authored-By: <agent/model> <email>` in commit messages — matching the existing repo plan `Docs/Agents/Plans/2026-06-30-copy-string-catalog.md` (agent identity is per-executor); the executor substitutes its own model name/email.

**Type/name consistency:** `CopyKey.statusResetsIn` (raw `"status.resetsIn"`, value "Resets in %@") is defined in Task 1 and consumed in Task 2's `rowContext`. The new signatures `rowContext(for:usage:relativeTo:calendar:)` and `homeSubtitle(...:calendar:)` (Task 2) are used with the trailing `calendar: utc` argument in every updated unit test, and left defaulted at the four production call sites. `isScheduledToday(at:calendar:)`, `Calendar.nextMidnight(after:)`, `RuleStatus.countdown(from:to:)`, and `RuleStatus.label(relativeTo:)` are used with the exact signatures verified in the source. `CopyKey.usageSubtitleSeparator` is retained (Task 3 removes only the four listed keys). Countdown expectations are consistent with the UTC test calendar: 11:38→midnight = "13h", 10:00→midnight = "14h", the unchanged Friday schedule case = "22h".

No gaps or inconsistencies found.
