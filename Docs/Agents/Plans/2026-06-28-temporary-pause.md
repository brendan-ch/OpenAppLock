# Temporary Pause Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the rest-of-window/day "Unblock" affordance with a 15-minute **Temporary Pause** (on the rule-viewing overlay) that re-engages the block automatically.

**Architecture:** Reuse the existing `pausedUntil` primitive (which already yields `.paused(until:)` from `RuleActivation`) and add a one-shot `pause-<uuid>` DeviceActivity re-arm modeled on the granted open session, so the shield re-engages in the background ~15 min later. Pause/Resume live on `RuleDetailSheet`; Home's Currently Blocking rows become navigational.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, FamilyControls/DeviceActivity/ManagedSettings, Swift Testing (`import Testing`) + XCUITest.

**Design spec:** `Docs/Agents/Specs/TEMPORARY_PAUSE.md` (read it first).

## Global Constraints

- **Pause duration: 15 minutes**, defined once as `MonitoringPlan.temporaryPauseMinutes = 15`.
- **Re-arm interval padding: +1 minute** over the pause (16-min activity) to stay above DeviceActivity's 15-minute floor — mirrors `MonitoringPlan.openSessionMinutes + 1`.
- **Supported kinds: `.schedule` and `.timeLimit` only.** `.openLimit` is never pausable.
- **Never pausable under Hard Mode**, and **only when the block has >15 min remaining**.
- **Build & test via the Xcode MCP only** (`BuildProject` / `RunSomeTests` / `RunAllTests`; get the tab id from `XcodeListWindows`). Never `xcodebuild`. Scheme destination must be an iOS **simulator**.
- **TDD:** write the failing test first; a compile failure counts as red. Run focused tests, then the full suite before completing a task.
- **Tests** use Swift Testing (`@Test`/`#expect`), the `utc` calendar and `date(...)` helper, and `makeInMemoryContext()` (TestSupport.swift). 2025-01-06 is a Monday.
- **Behavior source of truth is doc comments**; when a behavior changes, update the owning file's `///` doc comment in the same commit (AGENTS.md "Documentation").
- **Commit attribution (required):** every commit ends with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_019EtXqNtLHkbRCeD79yT9eh`.
- **Conventional commits** (`feat:`, `refactor:`, `test:`, `docs:`). Commit only as each task's final step.
- The spec doc (`Docs/Agents/Specs/TEMPORARY_PAUSE.md`) is currently untracked — `git add` it with Task 1's commit.

---

### Task 1: MonitoringPlan — pause duration + re-arm activity name

**Files:**
- Modify: `Shared/Platform/MonitoringPlan.swift`
- Test: `OpenAppLockTests/MonitoringPlanWarnTests.swift`
- Also stage: `Docs/Agents/Specs/TEMPORARY_PAUSE.md` (untracked)

**Interfaces:**
- Produces: `MonitoringPlan.temporaryPauseMinutes: Int` (== 15); `MonitoringPlan.pauseActivityName(for: UUID) -> String`; `MonitoringPlan.ruleID(fromPauseActivityName: String) -> UUID?`.

- [ ] **Step 1: Write the failing test** — append to `MonitoringPlanWarnTests.swift` (inside the `MonitoringPlanWarnTests` struct):

```swift
    @Test("Pause activity names round-trip rule IDs and don't collide with other activities")
    func pauseNameRoundTrip() {
        let id = UUID()
        let pause = MonitoringPlan.pauseActivityName(for: id)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: pause) == id)
        // Not mistaken for the daily, schedule-window, or warn activities…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: pause) == nil)
        #expect(MonitoringPlan.ruleID(fromScheduleWindowName: pause) == nil)
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: pause) == nil)
        // …and their names are not mistaken for a pause activity.
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: MonitoringPlan.dailyActivityName(for: id)) == nil)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: MonitoringPlan.scheduleWindowName(for: id)) == nil)
        #expect(MonitoringPlan.ruleID(fromPauseActivityName: "garbage") == nil)
        #expect(MonitoringPlan.temporaryPauseMinutes == 15)
    }
```

- [ ] **Step 2: Run the test to verify it fails** — Xcode MCP `RunSomeTests` for `OpenAppLockTests/MonitoringPlanWarnTests`. Expected: FAIL to compile — `pauseActivityName`/`temporaryPauseMinutes` not found.

- [ ] **Step 3: Implement** — in `MonitoringPlan.swift`, add the constant next to `openSessionMinutes`:

```swift
    /// Wall-clock length of a temporary pause. 15 minutes is DeviceActivity's
    /// minimum schedule interval, so the one-shot re-arm that re-engages the
    /// shield can fire right at the pause's end (with one extra minute of
    /// interval padding, as for granted opens).
    static let temporaryPauseMinutes = 15
```

  Add the prefix next to the other private prefixes:

```swift
    private static let pausePrefix = "pause-"
```

  Add the name helpers (e.g. after `sessionActivityName` / its parser):

```swift
    /// The one-shot activity that re-engages a rule's shield when its temporary
    /// pause ends. A distinct prefix means no other parser misclassifies it.
    static func pauseActivityName(for ruleID: UUID) -> String {
        pausePrefix + ruleID.uuidString
    }

    static func ruleID(fromPauseActivityName name: String) -> UUID? {
        guard name.hasPrefix(pausePrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(pausePrefix.count)))
    }
```

- [ ] **Step 4: Run the test to verify it passes** — `RunSomeTests` for `OpenAppLockTests/MonitoringPlanWarnTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Platform/MonitoringPlan.swift OpenAppLockTests/MonitoringPlanWarnTests.swift Docs/Agents/Specs/TEMPORARY_PAUSE.md
git commit -m "feat: add temporary-pause duration and re-arm activity name to MonitoringPlan"
```

---

### Task 2: RulePolicy — replace `unblock` with `pause` + `canPause` + `resume`

**Files:**
- Modify: `OpenAppLock/Logic/RulePolicy.swift`
- Modify (keep compiling): `OpenAppLock/Views/Home/HomeView.swift:79,114` (the two `canUnblock`/`unblock` call sites), `OpenAppLockTests/RuleEnforcerTests.swift:61`
- Test: `OpenAppLockTests/RulePolicyTests.swift`

**Interfaces:**
- Consumes: `RuleSnapshotDTO.activation(usage:at:calendar:) -> RuleActivation` (existing); `MonitoringPlan.temporaryPauseMinutes` (Task 1).
- Produces: `RulePolicy.canPause(_:usage:at:calendar:) -> Bool`; `RulePolicy.pause(_:usage:at:calendar:) -> Bool` (`@discardableResult`); `RulePolicy.resume(_:)`. (Removes `canUnblock`/`unblock`.)

- [ ] **Step 1: Write the failing tests** — replace the five unblock tests in the `RulePolicyTests` "Hard Mode policy" suite (the methods `hardLockedWhileActive` keeps its other asserts but swaps the unblock line; `softRuleUnblockable`, `unblockPausesUntilWindowEnd`, `hardModeUnblockRefused`, `inactiveUnblockRefused` are replaced) with:

```swift
    let mondayNearWindowEnd = date(2025, 1, 6, 16, 50)  // 10 min left in 09–17

    @Test("Active non-Hard-Mode rules may be paused")
    func softRulePausable() {
        let rule = rule(hardMode: false)
        #expect(RulePolicy.canPause(rule.dto, at: mondayDuringWork, calendar: utc))
    }

    @Test("Pausing sets pausedUntil 15 minutes out and reports paused")
    func pauseSetsFifteenMinutes() {
        let rule = rule(hardMode: false)
        let didPause = RulePolicy.pause(rule, at: mondayDuringWork, calendar: utc)
        #expect(didPause)
        #expect(rule.pausedUntil == date(2025, 1, 6, 10, 15))
        #expect(rule.dto.status(at: mondayDuringWork, calendar: utc)
            == .paused(until: date(2025, 1, 6, 10, 15)))
    }

    @Test("Pausing a Hard Mode rule is refused and changes nothing")
    func hardModePauseRefused() {
        let rule = rule(hardMode: true)
        #expect(!RulePolicy.pause(rule, at: mondayDuringWork, calendar: utc))
        #expect(rule.pausedUntil == nil)
        #expect(rule.dto.status(at: mondayDuringWork, calendar: utc).isActive)
    }

    @Test("Pausing an inactive rule is refused")
    func inactivePauseRefused() {
        let rule = rule(hardMode: false)
        #expect(!RulePolicy.pause(rule, at: mondayEvening, calendar: utc))
        #expect(rule.pausedUntil == nil)
    }

    @Test("Pause is unavailable when the block has 15 minutes or less left")
    func pauseHiddenNearWindowEnd() {
        let rule = rule(hardMode: false)
        #expect(!RulePolicy.canPause(rule.dto, at: mondayNearWindowEnd, calendar: utc))
        #expect(!RulePolicy.pause(rule, at: mondayNearWindowEnd, calendar: utc))
    }

    @Test("Open-limit rules are never pausable, even when blocking")
    func openLimitNotPausable() {
        let rule = BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
            days: Weekday.everyDay)
        let spent = RuleUsageDTO(opensUsed: 5)
        #expect(rule.dto.status(at: mondayDuringWork, calendar: utc, usage: spent).isActive)
        #expect(!RulePolicy.canPause(rule.dto, usage: spent, at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent time-limit rule is pausable")
    func timeLimitPausable() {
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        let spent = RuleUsageDTO(minutesUsed: 45)
        #expect(RulePolicy.canPause(rule.dto, usage: spent, at: mondayDuringWork, calendar: utc))
        #expect(RulePolicy.pause(rule, usage: spent, at: mondayDuringWork, calendar: utc))
        #expect(rule.pausedUntil == date(2025, 1, 6, 10, 15))
    }

    @Test("Resume clears the pause")
    func resumeClearsPause() {
        let rule = rule(hardMode: false)
        RulePolicy.pause(rule, at: mondayDuringWork, calendar: utc)
        #expect(rule.pausedUntil != nil)
        RulePolicy.resume(rule)
        #expect(rule.pausedUntil == nil)
    }
```

  And in `hardLockedWhileActive`, replace the `canUnblock` assertion line with:

```swift
        #expect(!RulePolicy.canPause(rule.dto, at: mondayDuringWork, calendar: utc))
```

- [ ] **Step 2: Run the tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/RulePolicyTests`. Expected: FAIL to compile — `canPause`/`pause`/`resume` not found.

- [ ] **Step 3: Implement RulePolicy** — in `RulePolicy.swift`, replace `canUnblock` and `unblock` (lines 50–131) with:

```swift
    /// Whether the user may temporarily pause the current block. Requires an
    /// active block, Hard Mode off, a pausable kind (schedule or time limit —
    /// open limits are never pausable), and more than `temporaryPauseMinutes`
    /// left on the block (a near-finished block isn't worth pausing, and this
    /// keeps the background re-arm above DeviceActivity's 15-minute floor).
    static func canPause(
        _ snapshot: RuleSnapshotDTO, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard !snapshot.hardMode,
            snapshot.kind == .schedule || snapshot.kind == .timeLimit,
            case let .active(until) = snapshot.activation(usage: usage, at: now, calendar: calendar)
        else { return false }
        return until.timeIntervalSince(now) > Double(MonitoringPlan.temporaryPauseMinutes * 60)
    }

    /// Temporarily pauses the rule's current block for `temporaryPauseMinutes`.
    /// Returns false (and changes nothing) when pausing is not allowed. The
    /// block re-arms on its own once the pause elapses (the derived status flips
    /// back to active; the foreground and the background re-arm re-apply the
    /// shield).
    @discardableResult
    static func pause(
        _ rule: BlockingRule, usage: RuleUsageDTO? = nil,
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard canPause(rule.dto, usage: usage, at: now, calendar: calendar) else { return false }
        rule.pausedUntil = calendar.date(
            byAdding: .minute, value: MonitoringPlan.temporaryPauseMinutes, to: now)
        return true
    }

    /// Ends a temporary pause immediately so the block re-engages now.
    static func resume(_ rule: BlockingRule) {
        rule.pausedUntil = nil
    }
```

  Update the type's header doc comment (lines 8–19): replace the "The one mutation, `unblock`…" sentence with one describing `pause`/`resume` and the temporary-pause semantics.

- [ ] **Step 4: Fix the two compile sites (keep the build green)** —

  In `HomeView.swift`, line 79 change `RulePolicy.canUnblock(` → `RulePolicy.canPause(`; line 114 change `RulePolicy.unblock(rule, usage: enforcer.usage(for: rule.dto))` → `RulePolicy.pause(rule, usage: enforcer.usage(for: rule.dto))`. (HomeView's inline UI is fully rewritten in Task 9; this is the minimal change to compile.)

  In `RuleEnforcerTests.swift`, line 61 change `RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)` → `RulePolicy.pause(rule, at: mondayDuringWork, calendar: utc)`.

- [ ] **Step 5: Run the tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/RulePolicyTests` and `OpenAppLockTests/RuleEnforcerTests`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Logic/RulePolicy.swift OpenAppLock/Views/Home/HomeView.swift OpenAppLockTests/RulePolicyTests.swift OpenAppLockTests/RuleEnforcerTests.swift
git commit -m "feat: replace unblock with a 15-minute temporary pause in RulePolicy"
```

---

### Task 3: RuleStatus — live countdown for the paused label

**Files:**
- Modify: `OpenAppLock/Logic/RuleStatus.swift:26-34`
- Test: `OpenAppLockTests/RuleStatusTests.swift`

**Interfaces:**
- Produces: `RuleStatus.paused(until:).label(relativeTo:)` now returns `"Resumes in <countdown>"`.

- [ ] **Step 1: Write/adjust the failing tests** — in `RuleStatusTests.swift`:
  - Replace the `paused()` test's label expectation by adding a label assertion:

```swift
    @Test("A paused rule reports paused with a resume countdown")
    func paused() {
        let rule = workTime()
        rule.pausedUntil = date(2025, 1, 6, 10, 15)
        let status = rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .paused(until: date(2025, 1, 6, 10, 15)))
        #expect(!status.isActive)
        #expect(status.label(relativeTo: date(2025, 1, 6, 10, 0)) == "Resumes in 15m")
    }
```

  - In `staticLabels()`, replace the paused line with:

```swift
        #expect(RuleStatus.paused(until: now.addingTimeInterval(15 * 60)).label(relativeTo: now) == "Resumes in 15m")
```

- [ ] **Step 2: Run the tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/RuleStatusTests`. Expected: FAIL — label is `"Paused"`, not `"Resumes in 15m"`.

- [ ] **Step 3: Implement** — in `RuleStatus.swift`, change the `.paused` case in `label(relativeTo:)`:

```swift
        case .paused(let until): "Resumes in \(Self.countdown(from: now, to: until))"
```

  Update the `case paused(until:)` doc comment (line 16) to: `/// The user temporarily paused the current block; it resumes at the associated date.`

- [ ] **Step 4: Run the tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/RuleStatusTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Logic/RuleStatus.swift OpenAppLockTests/RuleStatusTests.swift
git commit -m "feat: show a resume countdown on the paused rule status label"
```

---

### Task 4: LimitEnforcement — `handlePauseEnded`

**Files:**
- Modify: `Shared/Enforcement/LimitEnforcement.swift`
- Test: `OpenAppLockTests/SchedulingTests.swift` (the `LimitEnforcement` suite — search for the existing `handleOpenSessionEnded` / `LimitEnforcement` tests)

**Interfaces:**
- Consumes: `RuleSnapshotUserDefaultsStore`, `UsageLedger`, `ShieldApplying` (existing `LimitEnforcement` members); `RuleSnapshotDTO.isPaused(at:)`, `limitReached(given:at:)`.
- Produces: `LimitEnforcement.handlePauseEnded(ruleID:now:calendar:)`.

- [ ] **Step 1: Find the LimitEnforcement test harness** — open `OpenAppLockTests/SchedulingTests.swift`, locate the suite that builds a `LimitEnforcement` over a fresh `RuleSnapshotUserDefaultsStore` + `MockUsageLedger` + `MockShieldController` (the same shape used to test `handleOpenSessionEnded`/`handleUsageMinutes`). Reuse its helpers (`freshDefaults()`, snapshot-save helper) for the new tests.

- [ ] **Step 2: Write the failing tests** — add to that suite (adapt the local helper names to the file's existing ones):

```swift
    @Test("handlePauseEnded re-shields a spent, eligible time-limit rule")
    func pauseEndedReshieldsSpentTimeLimit() throws {
        let defaults = freshDefaults()
        let store = RuleSnapshotUserDefaultsStore(defaults: defaults)
        let ledger = MockUsageLedger()
        let shields = MockShieldController()
        let enforcement = LimitEnforcement(snapshots: store, ledger: ledger, shields: shields)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        store.save([rule.dto])
        ledger.usageByRule[rule.id] = RuleUsageDTO(minutesUsed: 45)

        enforcement.handlePauseEnded(ruleID: rule.id, now: date(2025, 1, 6, 10, 16), calendar: utc)

        #expect(shields.shieldedRuleIDs == [rule.id])
    }

    @Test("handlePauseEnded clears the shield while the pause is still in effect")
    func pauseEndedClearsWhilePaused() throws {
        let defaults = freshDefaults()
        let store = RuleSnapshotUserDefaultsStore(defaults: defaults)
        let ledger = MockUsageLedger()
        let shields = MockShieldController()
        let enforcement = LimitEnforcement(snapshots: store, ledger: ledger, shields: shields)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        rule.pausedUntil = date(2025, 1, 6, 10, 15)  // still paused at 10:00
        store.save([rule.dto])
        ledger.usageByRule[rule.id] = RuleUsageDTO(minutesUsed: 45)

        enforcement.handlePauseEnded(ruleID: rule.id, now: date(2025, 1, 6, 10, 0), calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }
```

- [ ] **Step 3: Run the tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/SchedulingTests`. Expected: FAIL to compile — `handlePauseEnded` not found.

- [ ] **Step 4: Implement** — in `LimitEnforcement.swift`, add (after `handleOpenSessionEnded`):

```swift
    /// A temporary pause on a time-limit rule reached an edge of its one-shot
    /// re-arm activity. Re-engage the shield when the budget is still spent and
    /// the rule is otherwise eligible, else clear. Called on both edges, so it
    /// clears while the pause is still in effect (`isPaused`) and re-shields a
    /// spent budget once it lapses. Schedule rules use `ScheduleEnforcement`.
    func handlePauseEnded(
        ruleID: UUID, now: Date = .now, calendar: Calendar = .current
    ) {
        let rid = ruleID.uuidString.prefix(8)
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
            snapshot.kind == .timeLimit, !snapshot.isPaused(at: now),
            snapshot.isScheduledToday(at: now, calendar: calendar),
            snapshot.limitReached(
                given: ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar), at: now)
        else {
            Diag.log(.scheduler, "pauseEnded rule-\(rid): clear (ineligible/under budget/still paused)")
            shields.clearShield(ruleID: ruleID)
            return
        }
        Diag.log(.scheduler, .event, "pauseEnded rule-\(rid): re-shield (budget spent)")
        shield(snapshot)
    }
```

- [ ] **Step 5: Run the tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/SchedulingTests`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Shared/Enforcement/LimitEnforcement.swift OpenAppLockTests/SchedulingTests.swift
git commit -m "feat: re-shield a spent time-limit when its temporary pause ends"
```

---

### Task 5: RuleScheduler — one-shot re-arm start/cancel + stale-pause reaping

**Files:**
- Modify: `OpenAppLock/Services/RuleScheduler.swift` (the `ActivityMonitoring` protocol, `DeviceActivityCenterMonitor`, `MockActivityMonitor`, and `RuleScheduler` itself)
- Test: `OpenAppLockTests/SchedulingTests.swift` (the `RuleSchedulerTests` suite)

**Interfaces:**
- Consumes: `MonitoringPlan.pauseActivityName(for:)`, `MonitoringPlan.ruleID(fromPauseActivityName:)` (Task 1).
- Produces: `ActivityMonitoring.startOneShotMonitoring(name:from:to:) throws`; `RuleScheduler.scheduleResumeReArm(for:until:now:calendar:)`; `RuleScheduler.cancelResumeReArm(for:)`; and `sync` now reaps stale `pause-` activities. `MockActivityMonitor.startedOneShots: [String: (start: Date, end: Date)]`.

- [ ] **Step 1: Write the failing tests** — add to the `RuleSchedulerTests` suite in `SchedulingTests.swift`:

```swift
    @Test("scheduleResumeReArm starts a one-shot pause activity")
    func schedulesPauseReArm() {
        let (scheduler, monitor, _) = makeScheduler()
        let id = UUID()
        scheduler.scheduleResumeReArm(
            for: id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        let name = MonitoringPlan.pauseActivityName(for: id)
        #expect(monitor.monitoredNames.contains(name))
        #expect(monitor.startedOneShots[name]?.end == date(2025, 1, 6, 10, 16))  // +1 padding
    }

    @Test("cancelResumeReArm stops the pause activity")
    func cancelsPauseReArm() {
        let (scheduler, monitor, _) = makeScheduler()
        let id = UUID()
        scheduler.scheduleResumeReArm(
            for: id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        scheduler.cancelResumeReArm(for: id)
        #expect(!monitor.monitoredNames.contains(MonitoringPlan.pauseActivityName(for: id)))
    }

    @Test("sync reaps a pause re-arm whose rule is no longer paused")
    func reapsStalePauseReArm() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)
        scheduler.scheduleResumeReArm(
            for: rule.id, until: date(2025, 1, 6, 10, 15),
            now: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(monitor.monitoredNames.contains(pauseName))

        scheduler.sync(rules: [rule])  // rule.pausedUntil == nil → reaped
        #expect(!monitor.monitoredNames.contains(pauseName))
    }

    @Test("sync keeps a pause re-arm for a still-paused rule")
    func keepsActivePauseReArm() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try scheduleRule(name: "Work Time", start: 9 * 60, end: 17 * 60)
        rule.pausedUntil = date(2025, 1, 6, 10, 15)
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)
        scheduler.scheduleResumeReArm(
            for: rule.id, until: rule.pausedUntil!,
            now: date(2025, 1, 6, 10, 0), calendar: utc)

        scheduler.sync(rules: [rule])
        #expect(monitor.monitoredNames.contains(pauseName))
    }
```

- [ ] **Step 2: Run the tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/SchedulingTests`. Expected: FAIL to compile — `startOneShotMonitoring`/`scheduleResumeReArm`/`cancelResumeReArm`/`startedOneShots` not found.

- [ ] **Step 3: Implement the protocol + monitors** — in `RuleScheduler.swift`:

  Add to the `ActivityMonitoring` protocol:

```swift
    /// Starts (or replaces) a one-shot activity spanning `start`…`end`
    /// wall-clock, carrying no events — used to re-engage a shield when a
    /// temporary pause ends (its `intervalDidEnd` wakes the monitor).
    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws
```

  Add to `DeviceActivityCenterMonitor`:

```swift
    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        try center.startMonitoring(DeviceActivityName(name), during: schedule)
    }
```

  Add to `MockActivityMonitor` (a new recorded field + the method):

```swift
    private(set) var startedOneShots: [String: (start: Date, end: Date)] = [:]

    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws {
        startCallCount += 1
        startedOneShots[name] = (start, end)
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }
```

- [ ] **Step 4: Implement the scheduler methods + reaping** — in `RuleScheduler`:

  Add the start/cancel methods:

```swift
    /// Starts the one-shot re-arm that re-engages `ruleID`'s shield when its
    /// temporary pause ends. The interval runs one minute past `pausedUntil` so
    /// it stays above DeviceActivity's 15-minute floor and `intervalDidEnd`
    /// fires after the pause has lapsed. Best-effort: the foreground
    /// reconciliation loop is the safety net.
    func scheduleResumeReArm(
        for ruleID: UUID, until pausedUntil: Date,
        now: Date = .now, calendar: Calendar = .current
    ) {
        guard let end = calendar.date(byAdding: .minute, value: 1, to: pausedUntil) else { return }
        let name = MonitoringPlan.pauseActivityName(for: ruleID)
        do {
            try monitor.startOneShotMonitoring(name: name, from: now, to: end)
            Diag.log(.scheduler, .event, "scheduled pause re-arm \(name)")
        } catch {
            Diag.error(.scheduler, "pause re-arm start failed \(name): \(error.localizedDescription)")
        }
    }

    /// Cancels a rule's pending pause re-arm (on resume, or when the pause is
    /// otherwise cleared). Safe to call when none is running.
    func cancelResumeReArm(for ruleID: UUID) {
        monitor.stopMonitoring(names: [MonitoringPlan.pauseActivityName(for: ruleID)])
    }

    /// Stops any `pause-` re-arm activity whose rule is no longer paused (or no
    /// longer exists) — the stop-only hygiene step that frees an activity slot
    /// after a disable/delete/resume/pause-clearing edit. Never starts a re-arm
    /// (that would push its interval forward every refresh and it would never
    /// fire), and keeps re-arms for not-yet-cleared (still `pausedUntil`) rules
    /// so a natural expiry's background re-shield still fires.
    private func reapStalePauseActivities(rules: [BlockingRule]) {
        let pausedRuleIDs = Set(rules.filter { $0.pausedUntil != nil }.map(\.id))
        let stale = monitor.monitoredNames.filter { name in
            guard let id = MonitoringPlan.ruleID(fromPauseActivityName: name) else { return false }
            return !pausedRuleIDs.contains(id)
        }
        guard !stale.isEmpty else { return }
        Diag.log(.scheduler, "reap \(stale.count) stale pause activities: \(stale.joined(separator: ","))")
        monitor.stopMonitoring(names: stale)
    }
```

  Call the reaping at the end of `sync(rules:at:)`, after `reconcile(plans)`:

```swift
        reconcile(plans)
        reapStalePauseActivities(rules: rules)
```

- [ ] **Step 5: Run the tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/SchedulingTests`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Services/RuleScheduler.swift OpenAppLockTests/SchedulingTests.swift
git commit -m "feat: schedule, cancel, and reap the temporary-pause re-arm activity"
```

---

### Task 6: RuleEnforcer — `pause` / `resume` orchestration

**Files:**
- Modify: `OpenAppLock/Services/RuleEnforcer.swift`
- Test: `OpenAppLockTests/RuleEnforcerTests.swift`

**Interfaces:**
- Consumes: `RulePolicy.pause`/`resume` (Task 2); `RuleScheduler.scheduleResumeReArm`/`cancelResumeReArm` (Task 5); existing `refresh(rules:at:calendar:)`, `usage(for:at:calendar:)`.
- Produces: `RuleEnforcer.pause(_:rules:at:calendar:) -> Bool` (`@discardableResult`); `RuleEnforcer.resume(_:rules:at:calendar:)`.

- [ ] **Step 1: Write the failing tests** — add to `RuleEnforcerTests` (the "Rule enforcement → shields" suite):

```swift
    @Test("Pausing an active rule clears its shield and sets a 15-minute pause")
    func pauseClearsShield() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")
        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(shields.shieldedRuleIDs == [rule.id])

        let didPause = enforcer.pause(rule, rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(didPause)
        #expect(rule.pausedUntil == date(2025, 1, 6, 10, 15))
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Resuming re-applies the shield and clears the pause")
    func resumeReshields() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")
        enforcer.pause(rule, rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(shields.shieldedRuleIDs.isEmpty)

        enforcer.resume(rule, rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(rule.pausedUntil == nil)
        #expect(shields.shieldedRuleIDs == [rule.id])
    }

    @Test("Pausing schedules a background re-arm; resuming cancels it")
    func pauseAndResumeManageReArm() {
        let shields = MockShieldController()
        let monitor = MockActivityMonitor()
        let suite = "enforcer-pause-\(UUID().uuidString)"
        let scheduler = RuleScheduler(
            monitor: monitor,
            snapshots: RuleSnapshotUserDefaultsStore(defaults: UserDefaults(suiteName: suite)!))
        let enforcer = RuleEnforcer(shields: shields, scheduler: scheduler)
        let rule = BlockingRule(name: "Work Time")
        // App lists are required for sync's normal monitoring, but the re-arm is
        // started directly by pause() regardless.
        let pauseName = MonitoringPlan.pauseActivityName(for: rule.id)

        enforcer.pause(rule, rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(monitor.monitoredNames.contains(pauseName))

        enforcer.resume(rule, rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(!monitor.monitoredNames.contains(pauseName))
    }
```

- [ ] **Step 2: Run the tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/RuleEnforcerTests`. Expected: FAIL to compile — `enforcer.pause`/`resume` not found.

- [ ] **Step 3: Implement** — in `RuleEnforcer.swift`, add (e.g. after `refresh`):

```swift
    /// Temporarily pauses the rule's current block: sets `pausedUntil` via
    /// `RulePolicy`, schedules the background re-arm, and refreshes so the
    /// shield clears immediately. No-op (returns false) when the rule can't be
    /// paused. `pausedUntil` is set before the refresh, so its reaping pass
    /// keeps the just-started re-arm.
    @discardableResult
    func pause(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) -> Bool {
        guard RulePolicy.pause(
            rule, usage: usage(for: rule.dto, at: now, calendar: calendar),
            at: now, calendar: calendar)
        else { return false }
        if let pausedUntil = rule.pausedUntil {
            scheduler?.scheduleResumeReArm(for: rule.id, until: pausedUntil, now: now, calendar: calendar)
        }
        refresh(rules: rules, at: now, calendar: calendar)
        return true
    }

    /// Ends a temporary pause now: clears `pausedUntil`, cancels the background
    /// re-arm, and refreshes so the shield re-engages immediately.
    func resume(
        _ rule: BlockingRule, rules: [BlockingRule],
        at now: Date = .now, calendar: Calendar = .current
    ) {
        RulePolicy.resume(rule)
        scheduler?.cancelResumeReArm(for: rule.id)
        refresh(rules: rules, at: now, calendar: calendar)
    }
```

- [ ] **Step 4: Run the tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/RuleEnforcerTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Services/RuleEnforcer.swift OpenAppLockTests/RuleEnforcerTests.swift
git commit -m "feat: orchestrate temporary pause and resume in RuleEnforcer"
```

---

### Task 7: Monitor extension — handle the `pause-` activity

**Files:**
- Modify: `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`

**Interfaces:**
- Consumes: `MonitoringPlan.ruleID(fromPauseActivityName:)` (Task 1); `LimitEnforcement.handlePauseEnded` (Task 4); `ScheduleEnforcement.reconcile` (existing); `RuleSnapshotUserDefaultsStore.snapshot(for:)`.
- Produces: background re-shield at a pause's end (no new unit surface; covered by Tasks 4 + existing ScheduleEnforcement tests).

- [ ] **Step 1: Implement the dispatcher** — in `DeviceActivityMonitorExtension.swift`, add a private helper:

```swift
    /// A temporary pause activity reached an interval edge: recompute the rule's
    /// shield from its snapshot. At the start edge the rule is still paused, so
    /// this clears; at the end edge the pause has lapsed, so it re-shields a
    /// still-blocking rule. Open limits are never pausable.
    private func reEnforceAfterPause(ruleID: UUID) {
        guard let snapshot = RuleSnapshotUserDefaultsStore().snapshot(for: ruleID) else { return }
        switch snapshot.kind {
        case .schedule: scheduleEnforcement.reconcile(ruleID: ruleID)
        case .timeLimit: enforcement.handlePauseEnded(ruleID: ruleID)
        case .openLimit: break
        }
    }
```

- [ ] **Step 2: Wire it into both interval edges** — in `intervalDidStart(for:)`, extend the `if/else if` chain (after the schedule-window branch) with:

```swift
        } else if let ruleID = MonitoringPlan.ruleID(fromPauseActivityName: activity.rawValue) {
            reEnforceAfterPause(ruleID: ruleID)
        }
```

  In `intervalDidEnd(for:)`, extend the chain (after the schedule-window branch) with:

```swift
        } else if let ruleID = MonitoringPlan.ruleID(fromPauseActivityName: activity.rawValue) {
            reEnforceAfterPause(ruleID: ruleID)
            DeviceActivityCenter().stopMonitoring([activity])
        }
```

- [ ] **Step 3: Build to verify it compiles** — Xcode MCP `BuildProject` (scheme `OpenAppLock`, an iOS simulator destination). Expected: build succeeds (the `OpenAppLockMonitor` extension target compiles). The dispatched logic is covered by Task 4 (`handlePauseEnded`) and the existing `ScheduleEnforcement` tests; the live `intervalDidEnd` re-shield is device-only (see spec §7).

- [ ] **Step 4: Commit**

```bash
git add OpenAppLockMonitor/DeviceActivityMonitorExtension.swift
git commit -m "feat: re-engage shields when a temporary pause activity ends"
```

---

### Task 8: RuleDetailSheet — Pause / Resume buttons + "Pausing allowed" row

**Files:**
- Modify: `OpenAppLock/Views/Rules/RuleDetailSheet.swift`
- Test: `OpenAppLockUITests/RuleManagementUITests.swift` (add a pause-flow test; update the 3 detail-row assertions)

**Interfaces:**
- Consumes: `RuleEnforcer.pause(_:rules:)` / `resume(_:rules:)` (Task 6); `RulePolicy.canPause` (Task 2); `RuleSnapshotDTO.isPaused(at:)`.
- Produces: detail-overlay `pauseRuleButton` / `resumeRuleButton`; the `detailRow-Pausing allowed` row (replacing `detailRow-Unblocks allowed`).

- [ ] **Step 1: Write the failing UI tests** — in `RuleManagementUITests.swift`, add a pause-flow test (reached via the Rules tab, so it's independent of Home):

```swift
    func testPauseActiveSoftRuleFromDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")
        app.goToRulesTab()
        app.buttons["ruleCard-Work Time"].waitToAppear().tap()

        app.buttons["pauseRuleButton"].waitToAppear().tap()
        // The confirmation dialog's button shares the row label, so scope to the sheet.
        app.sheets.buttons["Pause for 15 minutes"].waitToAppear().tap()

        // Paused → Resume replaces Pause, and the status reads a resume countdown.
        app.buttons["resumeRuleButton"].waitToAppear()
        XCTAssertTrue(app.staticTexts["detailStatusLabel"].label.contains("Resumes in"))

        // Resume re-blocks immediately.
        app.buttons["resumeRuleButton"].tap()
        app.buttons["pauseRuleButton"].waitToAppear()
    }
```

  Update the existing detail-row assertions (the "Unblocks allowed" row is renamed):
  - `testDetailShowsLiveStatusAndFacts`: change `app.element("detailRow-Unblocks allowed").exists` → `app.element("detailRow-Pausing allowed").exists`.
  - `testEditRuleTogglesHardModeOn`: change `app.element("detailRow-Unblocks allowed")` → `app.element("detailRow-Pausing allowed")`.
  - `HardModeUITests.testHardLockedRuleCannotBeEdited`: change `app.element("detailRow-Unblocks allowed").label.contains("No")` → `app.element("detailRow-Pausing allowed").label.contains("No")`.

- [ ] **Step 2: Run to verify failure** — `RunSomeTests` for `OpenAppLockUITests/RuleManagementUITests`. Expected: FAIL — `pauseRuleButton` / `detailRow-Pausing allowed` don't exist yet.

- [ ] **Step 3: Implement the buttons** — in `RuleDetailSheet.swift`:

  Add state + a rules query near the existing `@State` properties:

```swift
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]
    @State private var pendingPause = false
```

  (Add `import SwiftData` if not already imported — it is.)

  In `detailList(now:)`, make the actions `Section` show the pause/resume control above Edit Rule:

```swift
            Section {
                pauseOrResumeButton(dto: dto, usage: usage, now: now)
                if RulePolicy.canEdit(dto, usage: usage, at: now) {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Rule", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("editRuleButton")
                } else {
                    Label(
                        "Hard Mode is on — this rule is locked until the block ends.",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("hardModeLockedNotice")
                }
            }
```

  Add the builder (e.g. below `detailList`):

```swift
    /// Resume when paused; otherwise a confirmed "Pause for 15 minutes" when the
    /// block is pausable (schedule/time-limit, not Hard Mode, >15 min left).
    /// Nothing for an open-limit, hard-locked, or nearly-finished block. The
    /// Pause button is a plain (non-destructive) button so its icon and title
    /// share the standard tint.
    @ViewBuilder
    private func pauseOrResumeButton(
        dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date
    ) -> some View {
        if dto.isPaused(at: now) {
            Button {
                enforcer.resume(rule, rules: rules)
            } label: {
                Label("Resume Blocking", systemImage: "play.fill")
            }
            .accessibilityIdentifier("resumeRuleButton")
        } else if RulePolicy.canPause(dto, usage: usage, at: now) {
            Button {
                pendingPause = true
            } label: {
                Label("Pause for 15 minutes", systemImage: "pause.circle")
            }
            .accessibilityIdentifier("pauseRuleButton")
            .confirmationDialog(
                "Pause \(rule.name)?",
                isPresented: $pendingPause,
                titleVisibility: .visible
            ) {
                Button("Pause for 15 minutes") {
                    enforcer.pause(rule, rules: rules)
                    pendingPause = false
                }
            } message: {
                Text("Apps unblock for 15 minutes, then blocking resumes automatically.")
            }
        }
    }
```

- [ ] **Step 4: Rename the detail row** — in `detailRows`, change every `row("Unblocks allowed", rule.hardMode ? "No" : "Yes")` to:
  - `.schedule` and `.timeLimit` cases: `row("Pausing allowed", rule.hardMode ? "No" : "Yes")`
  - `.openLimit` case: `row("Pausing allowed", "No")` (open limits are never pausable).

  Update the type's header doc comment to mention the Pause/Resume action above Edit Rule.

- [ ] **Step 5: Run to verify passes** — `RunSomeTests` for `OpenAppLockUITests/RuleManagementUITests`. Expected: PASS. (If a CI run lands in the final 15 minutes of the day, the seeded Work Time window has ≤15 min left and Pause is correctly hidden — re-run; the gate's deterministic coverage is in Task 2's unit tests.)

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Views/Rules/RuleDetailSheet.swift OpenAppLockUITests/RuleManagementUITests.swift
git commit -m "feat: add Pause/Resume to the rule detail overlay"
```

---

### Task 9: HomeView — navigational Currently Blocking rows

**Files:**
- Modify: `OpenAppLock/Views/Home/HomeView.swift`
- Modify: `OpenAppLock/Views/Rules/RuleEditorView.swift:215` (footer copy)
- Test: `OpenAppLockUITests/RuleManagementUITests.swift` + `OpenAppLockUITests/UsageUITests.swift`

**Interfaces:**
- Consumes: the existing `detailRule` sheet + `RuleDetailSheet` (Task 8).
- Produces: Currently Blocking rows open the detail overlay; the inline unblock dialog, the Hard Mode alert, and their state are removed.

- [ ] **Step 1: Rework the UI tests** — these encode the old inline-unblock behavior and must move to navigation:

  In `RuleManagementUITests.swift`, replace `testUnblockActiveSoftRule` with:

```swift
    func testCurrentlyBlockingRowOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "standard")

        // The blocking rule's Home row now navigates to the detail overlay,
        // where Pause/Resume lives — no inline unblock dialog.
        app.buttons["blockedTile-Work Time"].waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Work Time")
        app.buttons["pauseRuleButton"].waitToAppear()
    }
```

  In `HardModeUITests`, replace `testHardLockedRuleCannotBeUnblocked` and delete `testSoftRuleUnblockOfferedButHardRuleRefused` with a single navigation test:

```swift
    func testHardLockedBlockingRowOffersNoPause() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "hard-mode-active")

        // The hard rule's Home row opens the detail overlay, which shows the
        // lock notice and no Pause button.
        app.buttons["blockedTile-Locked In"].waitToAppear().tap()
        app.element("hardModeLockedNotice").waitToAppear()
        XCTAssertFalse(app.buttons["pauseRuleButton"].exists)
        XCTAssertFalse(app.buttons["resumeRuleButton"].exists)
    }
```

  In `UsageUITests.swift`, replace `testSpentBudgetCanBeUnblockedUntilTomorrow` with:

```swift
    func testSpentBudgetRowOpensDetail() throws {
        let app = XCUIApplication.launchOpenAppLock(seedScenario: "limits")

        app.buttons["blockedTile-Doom Scroll"].waitToAppear().tap()
        XCTAssertEqual(app.staticTexts["detailRuleName"].waitToAppear().label, "Doom Scroll")
    }
```

- [ ] **Step 2: Run to verify failure** — `RunSomeTests` for `OpenAppLockUITests/RuleManagementUITests` and `OpenAppLockUITests/UsageUITests`. Expected: FAIL — the old row still opens the unblock dialog (no `detailRuleName` from a blocked tile).

- [ ] **Step 3: Implement the HomeView rewrite** — in `HomeView.swift`:

  Remove the two `@State` properties `unblockCandidate` and `hardModeBlockedAttempt` (keep `detailRule`).

  Remove the `.alert("Hard Mode is on", ...)` modifier from `body` (keep the `.sheet(item: $detailRule)`).

  Replace `blockingRow(for:now:)` entirely with:

```swift
    /// A blocking rule: leading kind icon, name, and a "<Type> · <context>"
    /// subtitle. Tapping opens the rule's detail overlay, where Pause/Resume
    /// (for supported, soft rules) lives.
    private func blockingRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsageDTO()
        let status = liveStatus(for: rule, now: now)
        return Button {
            detailRule = rule
        } label: {
            HStack {
                kindIcon(for: rule)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("blockedTile-\(rule.name)")
    }
```

- [ ] **Step 4: Update the editor footer copy** — in `RuleEditorView.swift`, change line 215:

```swift
            Text("This block can't be paused while it's active.")
```

- [ ] **Step 5: Run to verify passes** — `RunSomeTests` for `OpenAppLockUITests/RuleManagementUITests` and `OpenAppLockUITests/UsageUITests`. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add OpenAppLock/Views/Home/HomeView.swift OpenAppLock/Views/Rules/RuleEditorView.swift OpenAppLockUITests/RuleManagementUITests.swift OpenAppLockUITests/UsageUITests.swift
git commit -m "feat: open the detail overlay from Currently Blocking rows"
```

---

### Task 10: Documentation — doc comments + AGENTS.md

**Files:**
- Modify: `Shared/Models/RuleActivation.swift`, `OpenAppLock/Models/BlockingRule.swift`, `Shared/DTOs/RuleSnapshotDTO.swift`, `OpenAppLock/Services/RuleEnforcer.swift` (doc comments only), `Shared/Platform/MonitoringPlan.swift` (if any comment still says "unblock")
- Modify: `AGENTS.md`

**Interfaces:** none (documentation only).

- [ ] **Step 1: Update behavior doc comments** to replace "unblock"/"rest of the window/day" wording with the temporary-pause behavior:
  - `RuleActivation.swift` `case paused(until:)` comment (line ~25): `/// Would be blocking, but the user temporarily paused it until the associated date.`
  - `BlockingRule.swift` `pausedUntil` comment (lines ~42-43): `/// When set, the rule's current block is temporarily paused (user tapped Pause). Cleared automatically once the date passes; never set while Hard Mode is active.`
  - `RuleSnapshotDTO.swift` `isPaused(at:)` comment (line ~56): `/// Whether the user temporarily paused this rule (the pause has not yet elapsed).`
  - `RuleEnforcer.swift`: in the `refresh` doc (lines ~69-78), change "a soft unblock pauses only the rule it was invoked on" → "a temporary pause pauses only the rule it was invoked on"; in `expireStalePauseIfNeeded` (line ~126), "re-arms at its next window" → "re-arms once the pause elapses".

- [ ] **Step 2: Update AGENTS.md**:
  - Domain-facts **Hard Mode** bullet: replace "Soft rules can be \"unblocked\", which sets `pausedUntil` = window end (the rule re-arms at its next window)." with: "Soft rules support a **Temporary Pause** (`RulePolicy.pause`): a 15-minute lift (`pausedUntil = now + 15m`) for schedule/time-limit blocks with >15 min left, re-armed in the background by a one-shot `pause-<uuid>` DeviceActivity. Open limits and Hard Mode rules can't be paused."
  - Status line (Domain facts): keep `paused(until:)`; no change needed.
  - Rules-feature-map row: rename `| Unblock / disable / delete / Hard Mode gating | OpenAppLock/Logic/RulePolicy.swift |` → `| Temporary pause / disable / delete / Hard Mode gating | OpenAppLock/Logic/RulePolicy.swift |`.
  - UI-test gotcha bullet: replace "The unblock confirmation dialog is queried via `app.sheets.buttons[...]` (a bare `buttons["Unblock"]` is ambiguous with the row label)." with the pause equivalent: "The pause confirmation dialog is queried via `app.sheets.buttons["Pause for 15 minutes"]` (a bare match is ambiguous with the `pauseRuleButton` row label)."
  - Key accessibility identifiers list: add `pauseRuleButton`, `resumeRuleButton`; the detail rows reference is `detailRow-<label>` (no per-label change needed, but note "Pausing allowed" replaced "Unblocks allowed").

- [ ] **Step 3: Build to verify nothing broke** — `BuildProject` (comments-only change; confirm it still builds).

- [ ] **Step 4: Commit**

```bash
git add Shared/Models/RuleActivation.swift OpenAppLock/Models/BlockingRule.swift Shared/DTOs/RuleSnapshotDTO.swift OpenAppLock/Services/RuleEnforcer.swift Shared/Platform/MonitoringPlan.swift AGENTS.md
git commit -m "docs: document the temporary-pause behavior across source and AGENTS.md"
```

---

### Task 11: Full suite + spec status

**Files:**
- Modify: `Docs/Agents/Specs/TEMPORARY_PAUSE.md` (status line)

- [ ] **Step 1: Run the full unit + UI suite** — Xcode MCP `RunAllTests` (iOS simulator destination). Expected: all green. Per the flaky-tests note, if `RuleSchedulerTests`/`NotificationSettingsUITests` flake under the full parallel run, re-run them in isolation before treating it as a regression.

- [ ] **Step 2: Manual UI validation** — build & run the app on the simulator (`RunProject`); confirm: a blocking soft schedule rule's detail overlay shows "Pause for 15 minutes" above Edit Rule; confirming clears the block and the overlay shows "Resume Blocking" with a "Resumes in …" caption; Resume re-blocks; a hard-mode active rule shows the lock notice and no Pause; an open-limit rule shows no Pause. (Background re-arm at ~15 min is device-only — note it for hand-off, per spec §7.)

- [ ] **Step 3: Mark the spec implemented** — in `Docs/Agents/Specs/TEMPORARY_PAUSE.md`, change the status line to `Status: **Implemented** (2026-06-28) — full suite green; on-device re-arm verification pending (spec §7).`

- [ ] **Step 4: Commit**

```bash
git add Docs/Agents/Specs/TEMPORARY_PAUSE.md
git commit -m "docs: mark the temporary-pause spec implemented"
```

---

## Self-Review

**Spec coverage:**
- §2 availability gate (kinds, Hard Mode, >15 min) → Task 2 (`canPause`). Paused state label → Task 3. Open-limit exclusion → Task 2 + Task 8 row. ✓
- §3/§4.1 reuse `pausedUntil`, 15-min flat → Task 2; constant → Task 1. ✓
- §4.2 countdown label → Task 3. ✓
- §4.3 re-arm name/protocol/scheduler/enforcer → Tasks 1, 5, 6. ✓
- §4.4 monitor both-edges dispatch + `handlePauseEnded` → Tasks 7, 4. ✓
- §4.5 clash resistance (name isolation, `!isPaused` gating) is inherent in the reused paths; reaping (§3b) → Task 5. ✓
- §4.6 detail Pause/Resume + "Pausing allowed" → Task 8. §4.7 Home rows → Task 9. §4.8 editor copy → Task 9. ✓
- §5 docs → Task 10. §6 tests → Tasks 2–9. §7 device verification → Task 11 hand-off note. ✓

**Placeholder scan:** none — every step carries real code or an exact edit.

**Type consistency:** `canPause`/`pause`/`resume` (Task 2) consumed by Task 6 and Task 8; `temporaryPauseMinutes`/`pauseActivityName` (Task 1) consumed by Tasks 2, 5, 7; `startOneShotMonitoring`/`scheduleResumeReArm`/`cancelResumeReArm`/`startedOneShots` (Task 5) consumed by Task 6; `handlePauseEnded` (Task 4) consumed by Task 7; `pauseRuleButton`/`resumeRuleButton`/`detailRow-Pausing allowed` (Task 8) consumed by Task 9 tests. Names match across tasks. ✓
