# Time-Limit Day-Keyed Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every threshold-carrying time-limit DeviceActivity fire self-dating, so a cross-midnight stale flush is dropped at the monitor entry point before it can record a false block or post a spurious warn notification.

**Architecture:** Replace the always-on, repeating `rule-<uuid>` / `tlwarn-<uuid>` time-limit activities with per-day, non-repeating `rule-<uuid>-<dayKey>` / `tlwarn-<uuid>-<dayKey>` activities, armed only on scheduled days. The monitor drops any block/warn fire whose activity dayKey ≠ today. Open-limit and schedule rules keep their existing repeating activities.

**Tech Stack:** Swift 6, SwiftUI/SwiftData, FamilyControls/DeviceActivity/ManagedSettings, Swift Testing. Build/test via the **Xcode MCP** (`BuildProject`, `RunSomeTests`, `RunAllTests`) on an **iOS simulator** destination — never raw `xcodebuild`.

## Global Constraints

- Design source of truth is `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md`. Keep its §-numbered decisions intact.
- Day boundary is **local midnight** (`calendar.startOfDay`); the dayKey string is `UsageLedger.dayKey(for:calendar:)` (`"YYYY-MM-DD"`) — the single source for both the ledger key and the activity name suffix.
- Foreground arming horizon is **N = 2** scheduled occurrences (today/next scheduled day + the one after).
- `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`; cross-process value types stay `nonisolated`.
- Tests are Swift Testing (`@Test`/`#expect`), `@MainActor` suites, using `makeInMemoryContext()`, the `utc` calendar, `date(...)`, and a per-test `freshDefaults()` UserDefaults suite (see `OpenAppLockTests/TestSupport.swift`). No raw `xcodebuild`.
- Commit per task with a `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` trailer. Conventional-commit prefixes.
- Do not commit unless explicitly asked at execution time (project rule: "Commit only when the user asks"). The commit steps below are the intended boundaries; gate them on that rule.

---

## File Structure

- `Shared/Platform/MonitoringPlan.swift` — **modify.** Day-keyed name builders (`dayKey:` param), dayKey-tolerant parsers, `dayKey(fromActivityName:)`.
- `Shared/Models/ScheduledDayPlanner.swift` — **create.** Pure helpers: upcoming scheduled day-starts (N-ahead) and next scheduled day after a date. Reused by the scheduler (foreground) and the monitor (background self-arm).
- `OpenAppLock/Services/RuleScheduler.swift` — **modify.** New `.day` payload case + `startDayMonitoring`; per-day block/warn plan emission for time limits via one shared `dayPlan` builder; reconcile logging for `.day`.
- `Shared/Enforcement/LimitEnforcement.swift` — **modify.** `handleUsageMinutes(_:ruleID:activityDayKey:…)` stale-dayKey drop; confirm/zero unchanged in logic (now driven by the per-day block activity).
- `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift` — **modify.** Thread the activity dayKey into the block + warn paths; self-arm the next scheduled day at `intervalDidEnd`.
- `OpenAppLockMonitor/LimitWarningNotifier.swift` — **modify.** Accept the activity dayKey and drop a stale warn before notifying.
- Tests — **modify/create:** `OpenAppLockTests/SchedulingTests.swift`, `RuleSchedulerPlanTests.swift`, `RuleSchedulerWarnTests.swift`, `MonitoringPlanWarnTests.swift` (signature updates + new cases); new `OpenAppLockTests/ScheduledDayPlannerTests.swift`.
- Docs — **modify:** owning doc comments on the files above, `AGENTS.md` ("Rules feature map" + "Known gaps"), and the spec's status line.

---

## Task 1: Day-keyed naming & parsing (`MonitoringPlan`)

**Files:**
- Modify: `Shared/Platform/MonitoringPlan.swift`
- Test: `OpenAppLockTests/SchedulingTests.swift` (suite `MonitoringPlanTests`), `OpenAppLockTests/MonitoringPlanWarnTests.swift`

**Interfaces:**
- Consumes: `UUID.uuidString` (fixed 36 chars).
- Produces:
  - `MonitoringPlan.dailyActivityName(for: UUID, dayKey: String) -> String`
  - `MonitoringPlan.warnActivityName(for: UUID, dayKey: String) -> String`
  - `MonitoringPlan.ruleID(fromDailyActivityName: String) -> UUID?` (now tolerates a `-<dayKey>` suffix and the legacy un-keyed form)
  - `MonitoringPlan.ruleID(fromWarnActivityName: String) -> UUID?` (same)
  - `MonitoringPlan.dayKey(fromActivityName: String) -> String?`

- [ ] **Step 1: Write the failing tests**

In `OpenAppLockTests/SchedulingTests.swift`, replace the body of `MonitoringPlanTests.nameRoundTrip()` and add a day-key case:

```swift
    @Test("Activity names round-trip rule IDs, with and without a day key")
    func nameRoundTrip() {
        let id = UUID()
        let dayKey = "2026-06-29"
        let dayKeyed = MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)
        #expect(dayKeyed == "rule-\(id.uuidString)-2026-06-29")
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: dayKeyed) == id)
        #expect(MonitoringPlan.dayKey(fromActivityName: dayKeyed) == dayKey)
        // The legacy, un-keyed form (open-limit / pre-upgrade) still parses…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: "rule-\(id.uuidString)") == id)
        // …and reports no day key.
        #expect(MonitoringPlan.dayKey(fromActivityName: "rule-\(id.uuidString)") == nil)
        // Session names and garbage are not daily activities.
        #expect(
            MonitoringPlan.ruleID(
                fromSessionActivityName: MonitoringPlan.sessionActivityName(for: id)) == id)
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: "garbage") == nil)
        #expect(
            MonitoringPlan.ruleID(
                fromSessionActivityName: MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)) == nil)
    }
```

In `OpenAppLockTests/MonitoringPlanWarnTests.swift`, update `warnNameRoundTrip()`:

```swift
    @Test("Warn activity names round-trip rule IDs and don't collide with the block activity")
    func warnNameRoundTrip() {
        let id = UUID()
        let dayKey = "2026-06-29"
        let warn = MonitoringPlan.warnActivityName(for: id, dayKey: dayKey)
        #expect(warn == "tlwarn-\(id.uuidString)-2026-06-29")
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: warn) == id)
        #expect(MonitoringPlan.dayKey(fromActivityName: warn) == dayKey)
        // A warn name is not mistaken for the block (daily) activity…
        #expect(MonitoringPlan.ruleID(fromDailyActivityName: warn) == nil)
        // …and vice-versa.
        #expect(
            MonitoringPlan.ruleID(
                fromWarnActivityName: MonitoringPlan.dailyActivityName(for: id, dayKey: dayKey)) == nil)
        #expect(MonitoringPlan.ruleID(fromWarnActivityName: "garbage") == nil)
    }
```

Update `pauseNameRoundTrip()` in the same file: the two `dailyActivityName(for: id)` references become `dailyActivityName(for: id, dayKey: "2026-06-29")`.

- [ ] **Step 2: Run the tests to verify they fail**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/MonitoringPlanTests` and `OpenAppLockTests/MonitoringPlanWarnTests`.
Expected: FAIL to compile — `dailyActivityName(for:dayKey:)` / `dayKey(fromActivityName:)` don't exist yet.

- [ ] **Step 3: Implement the naming + parsing in `MonitoringPlan`**

Replace the daily/warn name builders and parsers in `Shared/Platform/MonitoringPlan.swift`:

```swift
    /// The per-day enforcement activity for a time-limit rule on `dayKey`
    /// (`UsageLedger.dayKey`, "YYYY-MM-DD"). The day key makes a cross-midnight
    /// stale flush self-identify: a callback tagged with a prior day's key is
    /// dropped on sight. Open-limit rules keep the legacy un-keyed `rule-<uuid>`.
    static func dailyActivityName(for ruleID: UUID, dayKey: String) -> String {
        dailyPrefix + ruleID.uuidString + "-" + dayKey
    }

    static func warnActivityName(for ruleID: UUID, dayKey: String) -> String {
        warnActivityPrefix + ruleID.uuidString + "-" + dayKey
    }

    static func ruleID(fromDailyActivityName name: String) -> UUID? {
        ruleID(in: name, afterPrefix: dailyPrefix)
    }

    static func ruleID(fromWarnActivityName name: String) -> UUID? {
        ruleID(in: name, afterPrefix: warnActivityPrefix)
    }

    /// The trailing `YYYY-MM-DD` of a day-keyed block or warn activity name, or
    /// nil for the legacy un-keyed form.
    static func dayKey(fromActivityName name: String) -> String? {
        for prefix in [dailyPrefix, warnActivityPrefix] where name.hasPrefix(prefix) {
            let body = name.dropFirst(prefix.count)
            guard body.count > uuidStringLength else { return nil }
            let suffix = body.dropFirst(uuidStringLength)
            guard suffix.hasPrefix("-") else { return nil }
            return String(suffix.dropFirst())
        }
        return nil
    }

    /// Recovers the rule UUID from `<prefix><uuid>` or `<prefix><uuid>-<dayKey>`.
    /// The UUID string is a fixed 36 characters, so any day-key suffix is ignored.
    private static func ruleID(in name: String, afterPrefix prefix: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        let body = name.dropFirst(prefix.count)
        guard body.count >= uuidStringLength else { return nil }
        return UUID(uuidString: String(body.prefix(uuidStringLength)))
    }

    private static let uuidStringLength = 36
```

Keep the existing `dailyPrefix`/`warnActivityPrefix` constants. Delete the old single-arg `dailyActivityName(for:)` / `warnActivityName(for:)` and the old prefix-drop parsers they replace.

- [ ] **Step 4: Run the tests to verify they pass**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/MonitoringPlanTests` and `OpenAppLockTests/MonitoringPlanWarnTests`.
Expected: the two updated round-trip tests PASS. (Other suites will not compile yet — that's Task 3's call-site updates; do not run the whole target here.)

- [ ] **Step 5: Commit**

```bash
git add Shared/Platform/MonitoringPlan.swift OpenAppLockTests/SchedulingTests.swift OpenAppLockTests/MonitoringPlanWarnTests.swift
git commit -m "feat: day-keyed time-limit activity names + tolerant parsers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Per-day monitor primitive (`.day` payload + `startDayMonitoring`)

**Files:**
- Modify: `OpenAppLock/Services/RuleScheduler.swift` (protocol `ActivityMonitoring`, `PlannedActivity.Payload`, `start(_:named:)`, `DeviceActivityCenterMonitor`, `MockActivityMonitor`)
- Test: `OpenAppLockTests/SchedulingTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ActivityMonitoring.startDayMonitoring(name: String, from: Date, to: Date, selectionData: Data?, eventMinutes: [String: Int]) throws`
  - `RuleScheduler.PlannedActivity.Payload.day(from: Date, to: Date, selectionData: Data?, eventMinutes: [String: Int])`
  - `MockActivityMonitor.startedDayWindows: [String: (from: Date, to: Date)]` (and `startedEvents[name]` keeps the event dict, as for `.daily`).

- [ ] **Step 1: Write the failing test**

Add to `OpenAppLockTests/SchedulingTests.swift` inside `RuleSchedulerTests`:

```swift
    @Test("startDayMonitoring records a dated, event-carrying window on the mock")
    func mockRecordsDayMonitoring() throws {
        let monitor = MockActivityMonitor()
        let from = date(2025, 1, 6)
        let to = date(2025, 1, 7)
        try monitor.startDayMonitoring(
            name: "rule-x-2025-01-06", from: from, to: to,
            selectionData: Data([1]), eventMinutes: ["minutes-45": 45])

        #expect(monitor.monitoredNames.contains("rule-x-2025-01-06"))
        #expect(monitor.startedEvents["rule-x-2025-01-06"]?["minutes-45"] == 45)
        #expect(monitor.startedDayWindows["rule-x-2025-01-06"]?.from == from)
        #expect(monitor.startedDayWindows["rule-x-2025-01-06"]?.to == to)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/RuleSchedulerTests/mockRecordsDayMonitoring`.
Expected: FAIL to compile — `startDayMonitoring` / `startedDayWindows` don't exist.

- [ ] **Step 3: Implement the primitive**

In `OpenAppLock/Services/RuleScheduler.swift`, add to the `ActivityMonitoring` protocol:

```swift
    /// Starts (or replaces) a one-shot day window spanning `from`…`to`
    /// wall-clock, carrying usage-threshold `eventMinutes` over the selection —
    /// used for a time-limit rule's self-dating per-day enforcement activity.
    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws
```

Add the payload case to `PlannedActivity.Payload`:

```swift
            case day(from: Date, to: Date, selectionData: Data?, eventMinutes: [String: Int])
```

Extend `start(_:named:)` with the new case:

```swift
        case let .day(from, to, selectionData, eventMinutes):
            try monitor.startDayMonitoring(
                name: name, from: from, to: to,
                selectionData: selectionData, eventMinutes: eventMinutes)
```

Implement on `DeviceActivityCenterMonitor` (device path — mirrors `startOneShotMonitoring` for the schedule, `startDailyMonitoring` for the events):

```swift
    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        let selection = AppSelectionCodec.decode(selectionData)
        let events = Dictionary(
            uniqueKeysWithValues: eventMinutes.map { eventName, minutes in
                (
                    DeviceActivityEvent.Name(eventName),
                    DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes)
                    )
                )
            }
        )
        try center.startMonitoring(DeviceActivityName(name), during: schedule, events: events)
    }
```

Implement on `MockActivityMonitor` (add a stored property and the method):

```swift
    private(set) var startedDayWindows: [String: (from: Date, to: Date)] = [:]

    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        startCallCount += 1
        startedEvents[name] = eventMinutes
        startedDayWindows[name] = (start, end)
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }
```

Also clear `startedDayWindows[name] = nil` inside `MockActivityMonitor.stopMonitoring(names:)`, alongside the existing `startedEvents`/`startedWindows` clears.

- [ ] **Step 4: Run the test to verify it passes**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/RuleSchedulerTests/mockRecordsDayMonitoring`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Services/RuleScheduler.swift OpenAppLockTests/SchedulingTests.swift
git commit -m "feat: add dated event-carrying day-window monitoring primitive

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Per-day plan emission in `RuleScheduler.sync` (foreground N=2 arming)

**Files:**
- Create: `Shared/Models/ScheduledDayPlanner.swift`
- Modify: `OpenAppLock/Services/RuleScheduler.swift` (`sync`, new `dayPlan` builder; `reconcile` logging for `.day`)
- Test: `OpenAppLockTests/ScheduledDayPlannerTests.swift` (create), `OpenAppLockTests/SchedulingTests.swift`, `OpenAppLockTests/RuleSchedulerPlanTests.swift`, `OpenAppLockTests/RuleSchedulerWarnTests.swift` (call-site updates + new cases)

**Interfaces:**
- Consumes: `MonitoringPlan.dailyActivityName(for:dayKey:)`, `MonitoringPlan.warnActivityName(for:dayKey:)`, `UsageLedger.dayKey(for:calendar:)`, `PlannedActivity.Payload.day(...)`, `BlockingRule.days`/`kind`/`dailyLimitMinutes`/`id`.
- Produces:
  - `ScheduledDayPlanner.upcomingScheduledDayStarts(days: Set<Weekday>, from: Date, count: Int, calendar: Calendar) -> [Date]`
  - `ScheduledDayPlanner.nextScheduledDayStart(after: Date, days: Set<Weekday>, calendar: Calendar) -> Date?`
  - `RuleScheduler.dayActivityHorizon = 2` (the N).
  - `sync` now emits, per scheduled day in the horizon, a block `.day` plan (name `rule-<uuid>-<dayKey>`, event `blockEvent`, fingerprint `"<kindRaw>|<budget>|<selFP>"`, `resetsThresholdAccountingOnRestart: true`) and, when the nudge is on and the budget exceeds the lead, a warn `.day` plan (name `tlwarn-<uuid>-<dayKey>`, event `warnEvent`, fingerprint `"tlwarn|<budget>|<selFP>"`, reset flag false). Open-limit rules still emit the single legacy `limitPlan`.

- [ ] **Step 1: Write the failing planner tests**

Create `OpenAppLockTests/ScheduledDayPlannerTests.swift`:

```swift
//
//  ScheduledDayPlannerTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Scheduled day planner")
struct ScheduledDayPlannerTests {
    @Test("Upcoming day-starts include today when scheduled, then the next scheduled days")
    func everyDayHorizon() {
        // 2025-01-06 is a Monday (10:00). Every-day rule → today + tomorrow.
        let now = date(2025, 1, 6, 10, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.everyDay, from: now, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 6), date(2025, 1, 7)])
    }

    @Test("Upcoming day-starts skip non-scheduled weekdays")
    func weekdaysHorizonFromFriday() {
        // 2025-01-10 is a Friday. Weekdays-only → Friday, then Monday (skips weekend).
        let friday = date(2025, 1, 10, 9, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.weekdays, from: friday, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 10), date(2025, 1, 13)])
    }

    @Test("Upcoming day-starts start from the next scheduled day when today is not scheduled")
    func startsAtNextScheduledDay() {
        // 2025-01-11 is a Saturday; weekdays-only → next is Monday + Tuesday.
        let saturday = date(2025, 1, 11, 9, 0)
        let days = ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: Weekday.weekdays, from: saturday, count: 2, calendar: utc)
        #expect(days == [date(2025, 1, 13), date(2025, 1, 14)])
    }

    @Test("No scheduled days yields an empty horizon")
    func emptyDays() {
        let now = date(2025, 1, 6, 10, 0)
        #expect(
            ScheduledDayPlanner.upcomingScheduledDayStarts(
                days: [], from: now, count: 2, calendar: utc).isEmpty)
    }

    @Test("Next scheduled day-start after a given day skips non-scheduled weekdays")
    func nextAfter() {
        // After Friday 2025-01-10, weekdays-only → Monday 2025-01-13.
        let next = ScheduledDayPlanner.nextScheduledDayStart(
            after: date(2025, 1, 10), days: Weekday.weekdays, calendar: utc)
        #expect(next == date(2025, 1, 13))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/ScheduledDayPlannerTests`.
Expected: FAIL to compile — `ScheduledDayPlanner` doesn't exist.

- [ ] **Step 3: Implement `ScheduledDayPlanner`**

Create `Shared/Models/ScheduledDayPlanner.swift`:

```swift
//
//  ScheduledDayPlanner.swift
//  OpenAppLock
//

import Foundation

/// Pure day-granularity scheduling helpers shared by the foreground scheduler
/// (which arms the next N scheduled per-day activities) and the background
/// monitor (which self-arms the next scheduled day when one ends). Weekday
/// membership only — windows/usage live elsewhere.
nonisolated enum ScheduledDayPlanner {
    private static let searchHorizonDays = 14

    /// Up to `count` `startOfDay` Dates, beginning at the day containing `now`,
    /// on which `days` schedules the rule. Empty when `days` is empty.
    static func upcomingScheduledDayStarts(
        days: Set<Weekday>, from now: Date, count: Int, calendar: Calendar = .current
    ) -> [Date] {
        guard !days.isEmpty, count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [Date] = []
        var offset = 0
        while result.count < count, offset < searchHorizonDays {
            if let day = calendar.date(byAdding: .day, value: offset, to: today),
               let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
               days.contains(weekday) {
                result.append(day)
            }
            offset += 1
        }
        return result
    }

    /// The `startOfDay` of the first scheduled day strictly after the day
    /// containing `day`, or nil when none falls inside the search horizon.
    static func nextScheduledDayStart(
        after day: Date, days: Set<Weekday>, calendar: Calendar = .current
    ) -> Date? {
        guard !days.isEmpty else { return nil }
        let base = calendar.startOfDay(for: day)
        for offset in 1...searchHorizonDays {
            if let candidate = calendar.date(byAdding: .day, value: offset, to: base),
               let weekday = Weekday(rawValue: calendar.component(.weekday, from: candidate)),
               days.contains(weekday) {
                return candidate
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run to verify the planner tests pass**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/ScheduledDayPlannerTests`.
Expected: PASS.

- [ ] **Step 5: Write the failing per-day emission test**

Add to `OpenAppLockTests/SchedulingTests.swift` inside `RuleSchedulerTests` (the `makeScheduler()`/`limitRule(kind:name:)` helpers there default to every-day rules):

```swift
    @Test("A time limit arms a per-day block activity for today and tomorrow")
    func timeLimitArmsTwoDayKeyedActivities() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")
        let now = date(2025, 1, 6, 10, 0)

        scheduler.sync(rules: [rule], at: now)

        let today = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: .current))
        let tomorrow = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 7), calendar: .current))
        #expect(monitor.monitoredNames.contains(today))
        #expect(monitor.monitoredNames.contains(tomorrow))
        #expect(monitor.startedEvents[today]?[MonitoringPlan.minuteEventName(for: rule.dailyLimitMinutes)]
            == rule.dailyLimitMinutes)
        // No legacy un-keyed daily activity is armed for a time limit.
        #expect(!monitor.monitoredNames.contains("rule-\(rule.id.uuidString)"))
    }

    @Test("Rolling the day forward arms the new day and reaps the day that fell out of the horizon")
    func dayRolloverReapsPastActivity() throws {
        let (scheduler, monitor, _) = makeScheduler()
        let rule = try limitRule(kind: .timeLimit, name: "Time Keeper")

        scheduler.sync(rules: [rule], at: date(2025, 1, 6, 10, 0))   // arms 01-06, 01-07
        scheduler.sync(rules: [rule], at: date(2025, 1, 7, 10, 0))   // arms 01-07, 01-08

        let jan6 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 6), calendar: .current))
        let jan8 = MonitoringPlan.dailyActivityName(
            for: rule.id, dayKey: UsageLedger.dayKey(for: date(2025, 1, 8), calendar: .current))
        #expect(!monitor.monitoredNames.contains(jan6))   // reaped
        #expect(monitor.monitoredNames.contains(jan8))    // newly armed
    }
```

Note: these tests use `.current` for the dayKey to match `sync`'s default calendar; `sync(rules:at:)` already takes a `now`, and the scheduler's calendar is `.current`. (If `sync` is given a `calendar` parameter during implementation, pass `utc` consistently in the test and the call.)

- [ ] **Step 6: Run to verify failure**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/RuleSchedulerTests/timeLimitArmsTwoDayKeyedActivities` and `.../dayRolloverReapsPastActivity`.
Expected: FAIL — only the legacy single activity is armed (or compile error if `sync` lacks the day logic).

- [ ] **Step 7: Implement per-day emission in `sync`**

In `OpenAppLock/Services/RuleScheduler.swift`:

Add the horizon constant near the top of `RuleScheduler`:

```swift
    /// How many upcoming scheduled days a time-limit rule arms ahead (today/next
    /// + the one after), so the next day is registered before its midnight even
    /// without a monitor self-arm. See the day-keyed enforcement spec §5.
    static let dayActivityHorizon = 2
```

Replace the `case .timeLimit, .openLimit:` arm of the `for rule in rules` loop in `sync(rules:at:)` so time limits go per-day and open limits keep the legacy plan:

```swift
            switch rule.kind {
            case .timeLimit:
                plans.append(contentsOf: dayPlans(for: rule, selectionData: selectionData, at: now))
            case .openLimit:
                plans.append(limitPlan(for: rule, selectionData: selectionData))
            case .schedule:
                plans.append(contentsOf: schedulePlans(for: rule))
            }
```

Add the per-day builder (one shared builder for block + warn):

```swift
    /// The per-day block (and, when opted in, warn) activities for a time-limit
    /// rule across the next `dayActivityHorizon` scheduled days. Each is a
    /// non-repeating `.day` window spanning that day, so a cross-midnight stale
    /// flush carries a prior day key and is dropped by the monitor.
    func dayPlans(
        for rule: BlockingRule, selectionData: Data,
        at now: Date, calendar: Calendar = .current
    ) -> [PlannedActivity] {
        let selectionFP = Self.selectionFingerprint(selectionData)
        let nudgeOn = NotificationPreferences(defaults: defaults).timeLimitEndingEnabled
        let warnEvents = MonitoringPlan.warnEvent(forLimit: rule.dailyLimitMinutes)
        var plans: [PlannedActivity] = []
        for dayStart in ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: rule.days, from: now, count: Self.dayActivityHorizon, calendar: calendar)
        {
            let dayKey = UsageLedger.dayKey(for: dayStart, calendar: calendar)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            plans.append(
                PlannedActivity(
                    name: MonitoringPlan.dailyActivityName(for: rule.id, dayKey: dayKey),
                    fingerprint: "\(rule.kindRaw)|\(rule.dailyLimitMinutes)|\(selectionFP)",
                    payload: .day(
                        from: dayStart, to: dayEnd, selectionData: selectionData,
                        eventMinutes: MonitoringPlan.blockEvent(forLimit: rule.dailyLimitMinutes)),
                    resetsThresholdAccountingOnRestart: true))
            if nudgeOn, let warnEvents {
                plans.append(
                    PlannedActivity(
                        name: MonitoringPlan.warnActivityName(for: rule.id, dayKey: dayKey),
                        fingerprint: "tlwarn|\(rule.dailyLimitMinutes)|\(selectionFP)",
                        payload: .day(
                            from: dayStart, to: dayEnd, selectionData: selectionData,
                            eventMinutes: warnEvents),
                        resetsThresholdAccountingOnRestart: false))
            }
        }
        return plans
    }
```

Update the `reconcile` reset-accounting log so the `.day` block payload is covered (the `if plan.resetsThresholdAccountingOnRestart` branch currently only matches `.daily`):

```swift
            if plan.resetsThresholdAccountingOnRestart {
                let events: [String: Int]
                switch plan.payload {
                case let .daily(_, e): events = e
                case let .day(_, _, _, e): events = e
                case .window: events = [:]
                }
                Diag.log(
                    .scheduler, .event,
                    "dailyActivity restart \(plan.name): events=\(events) fp \(Self.shortFingerprint(fingerprints[plan.name]))->\(Self.shortFingerprint(plan.fingerprint)) (resets threshold accounting)")
            }
```

(`limitPlan` and `warnPlan` remain for open-limit / direct unit tests; the time-limit path no longer calls them.)

- [ ] **Step 8: Update existing call sites broken by the signature change**

`RuleSchedulerPlanTests.swift` and `RuleSchedulerWarnTests.swift` reference `MonitoringPlan.dailyActivityName(for: rule.id)` / `warnActivityName(for: rule.id)` and assert `limitPlan`/`warnPlan` shapes. The `limitPlan`/`warnPlan` direct-unit tests still pass (those methods are unchanged and still used by open-limit), but every `dailyActivityName(for: id)` / `warnActivityName(for: id)` reference must gain a `dayKey:`. For the monitor-driven sync tests in `RuleSchedulerWarnTests` (`registersWarnActivityWhenEnabled`, etc.), update the expected names to the day-keyed today form and pass a fixed `now`:

```swift
    @Test("Opted-in time limit registers a per-day warn activity 5 min before the budget")
    func registersWarnActivityWhenEnabled() throws {
        let defaults = freshDefaults(timeLimitNotify: true)
        let (scheduler, monitor) = makeScheduler(defaults: defaults)
        let rule = try timeLimitRule(limit: 60)
        let now = date(2025, 1, 6, 10, 0)

        scheduler.sync(rules: [rule], at: now)

        let dayKey = UsageLedger.dayKey(for: date(2025, 1, 6), calendar: .current)
        let blockName = MonitoringPlan.dailyActivityName(for: rule.id, dayKey: dayKey)
        let warnName = MonitoringPlan.warnActivityName(for: rule.id, dayKey: dayKey)
        #expect(monitor.monitoredNames.contains(blockName))
        #expect(monitor.monitoredNames.contains(warnName))
        #expect(monitor.startedEvents[warnName]?["warn-55"] == 55)
        #expect(monitor.startedEvents[blockName]?[MonitoringPlan.minuteEventName(for: 60)] == 60)
    }
```

Apply the same `dayKey:` + `at: now` updates to `noWarnActivityWhenDisabled`, `noWarnActivityForTinyBudget`, and `togglingNudgeLeavesBlockActivityUntouched`. For the toggle test, the block start count is now **2** (today + tomorrow) instead of 1; assert `startCallCount == 2` after the first sync, `== 4` after enabling the nudge (two warn days added, block untouched), and `== 4` after disabling (warn days stopped, block untouched).

In `SchedulingTests.swift` `RuleSchedulerTests`: `startsMonitoring` and `openLimitHasNoCheckpoints` reference `dailyActivityName(for: rule.id)`. `openLimitHasNoCheckpoints` stays legacy (open-limit keeps the un-keyed name). `startsMonitoring` is superseded by `timeLimitArmsTwoDayKeyedActivities` (Step 5) — replace its body with that assertion or delete it in favor of the new test. The "Unchanged rules are not restarted" test (`unchangedRulesNotRestarted`) must pass a fixed `at:` to both syncs so the dayKey is identical across calls (otherwise a real day change would legitimately restart).

- [ ] **Step 9: Run the scheduler suites to verify green**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/RuleSchedulerTests`, `OpenAppLockTests/RuleSchedulerWarnTests`, `OpenAppLockTests/RuleSchedulerPlanTests`, `OpenAppLockTests/ScheduledDayPlannerTests`.
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add Shared/Models/ScheduledDayPlanner.swift OpenAppLock/Services/RuleScheduler.swift OpenAppLockTests/ScheduledDayPlannerTests.swift OpenAppLockTests/SchedulingTests.swift OpenAppLockTests/RuleSchedulerWarnTests.swift OpenAppLockTests/RuleSchedulerPlanTests.swift
git commit -m "feat: arm per-day time-limit activities for the next N scheduled days

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Stale-dayKey drop (`LimitEnforcement` + monitor wiring)

**Files:**
- Modify: `Shared/Enforcement/LimitEnforcement.swift` (`handleUsageMinutes` gains `activityDayKey`)
- Modify: `OpenAppLockMonitor/LimitWarningNotifier.swift` (`notifyIfEligible` gains `activityDayKey`)
- Modify: `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift` (thread the dayKey from the activity name)
- Test: `OpenAppLockTests/SchedulingTests.swift` (`LimitEnforcementTests`)

**Interfaces:**
- Consumes: `MonitoringPlan.dayKey(fromActivityName:)`, `UsageLedger.dayKey(for:calendar:)`.
- Produces:
  - `LimitEnforcement.handleUsageMinutes(_ minutes: Int, ruleID: UUID, activityDayKey: String?, now: Date, calendar: Calendar)` — drops when `activityDayKey != nil && activityDayKey != UsageLedger.dayKey(for: now)`.
  - `LimitWarningNotifier.notifyIfEligible(ruleID: UUID, activityDayKey: String?, now: Date, calendar: Calendar)` — drops a stale-dayKey warn before composing.

- [ ] **Step 1: Write the failing tests**

Add to `OpenAppLockTests/SchedulingTests.swift` inside `LimitEnforcementTests`:

```swift
    @Test("A usage checkpoint tagged with a prior day key is dropped (cross-midnight flush)")
    func staleDayKeyedCheckpointDropped() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 30)
        store.save([snap])
        // It is 2025-01-07 01:33; today's interval has started…
        let today = date(2025, 1, 7, 1, 33)
        enforcement.handleDayStart(ruleID: snap.id, now: today, calendar: utc)
        // …but the budget event is tagged with YESTERDAY (2025-01-06): a flush.
        enforcement.handleUsageMinutes(
            30, ruleID: snap.id, activityDayKey: "2025-01-06", now: today, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: today, calendar: utc).minutesUsed == 0)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("A usage checkpoint tagged with today's day key still records and shields")
    func todayDayKeyedCheckpointHonoured() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 30)
        store.save([snap])
        let today = date(2025, 1, 6, 10, 0)
        enforcement.handleDayStart(ruleID: snap.id, now: today, calendar: utc)
        enforcement.handleUsageMinutes(
            30, ruleID: snap.id, activityDayKey: "2025-01-06", now: today, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: today, calendar: utc).minutesUsed == 30)
        #expect(shields.shieldedRuleIDs == [snap.id])
    }
```

Update the existing `LimitEnforcementTests` calls to `handleUsageMinutes(...)` to pass `activityDayKey: nil` (legacy/defensive path keeps the prior guards) — `ineligibleRuleDoesNotAccrue`, `usageCheckpointsShieldAtLimit`, `staleCrossMidnightCheckpointIgnored`, `freshCheckpointWithinElapsedHonoured`, `checkpointBeforeConfirmedStartDropped`, `dayStartZeroesOnceOnTransition`.

- [ ] **Step 2: Run to verify failure**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`.
Expected: FAIL to compile — `handleUsageMinutes` has no `activityDayKey:` parameter.

- [ ] **Step 3: Implement the drop in `handleUsageMinutes`**

In `Shared/Enforcement/LimitEnforcement.swift`, change the signature and add the dayKey gate as the **first** guard (before the magnitude guard):

```swift
    /// A cumulative usage checkpoint fired for a time-limit rule. `activityDayKey`
    /// is the day key parsed from the firing activity's name (nil for a legacy
    /// un-keyed activity); a checkpoint tagged with any day other than today is a
    /// cross-midnight stale flush from a prior day's activity and is dropped.
    func handleUsageMinutes(
        _ minutes: Int, ruleID: UUID, activityDayKey: String? = nil,
        now: Date = .now, calendar: Calendar = .current
    ) {
        let rid = ruleID.uuidString.prefix(8)
        let today = UsageLedger.dayKey(for: now, calendar: calendar)
        if let activityDayKey, activityDayKey != today {
            Diag.log(
                .usage,
                "drop rule-\(rid): stale day-keyed flush (activity=\(activityDayKey) today=\(today))")
            return
        }
        // … existing body unchanged from the `minutesSinceMidnight` line down …
```

Keep the rest of the method (magnitude guard, confirmed-start gate, eligibility guard, record, shield) exactly as-is — they remain as defense-in-depth (spec §6).

- [ ] **Step 4: Run to verify the LimitEnforcement tests pass**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`.
Expected: PASS.

- [ ] **Step 5: Thread the dayKey through the monitor (build-verified — block + warn)**

In `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`, in `eventDidReachThreshold`, pass the parsed dayKey on both paths:

```swift
        if let ruleID = MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) {
            LimitWarningNotifier().notifyIfEligible(
                ruleID: ruleID, activityDayKey: MonitoringPlan.dayKey(fromActivityName: activity.rawValue))
            return
        }
        guard let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue),
              let minutes = MonitoringPlan.minutes(fromEventName: event.rawValue)
        else { return }
        enforcement.handleUsageMinutes(
            minutes, ruleID: ruleID,
            activityDayKey: MonitoringPlan.dayKey(fromActivityName: activity.rawValue))
        uninstallProtection.reconcile()
```

In `OpenAppLockMonitor/LimitWarningNotifier.swift`, add the parameter and drop a stale warn before composing:

```swift
    func notifyIfEligible(
        ruleID: UUID, activityDayKey: String? = nil,
        now: Date = .now, calendar: Calendar = .current
    ) {
        if let activityDayKey, activityDayKey != UsageLedger.dayKey(for: now, calendar: calendar) {
            return
        }
        // … existing body unchanged …
    }
```

- [ ] **Step 6: Build to verify the monitor target compiles**

Xcode MCP `BuildProject` (scheme `OpenAppLock`, simulator destination).
Expected: build succeeds (no simulator DeviceActivity behavior to assert here — drop logic is covered by the Task 4 unit tests; on-device behavior is a §14 verification item).

- [ ] **Step 7: Commit**

```bash
git add Shared/Enforcement/LimitEnforcement.swift OpenAppLockMonitor/DeviceActivityMonitorExtension.swift OpenAppLockMonitor/LimitWarningNotifier.swift OpenAppLockTests/SchedulingTests.swift
git commit -m "feat: drop cross-midnight stale time-limit fires by activity day key

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Background self-arm at `intervalDidEnd` (device-verified)

**Files:**
- Modify: `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift` (`intervalDidEnd` self-arms the next scheduled day for a block/warn activity)
- Test: `OpenAppLockTests/ScheduledDayPlannerTests.swift` already covers `nextScheduledDayStart` (Task 3); the monitor `startMonitoring` call itself is device-only.

**Interfaces:**
- Consumes: `MonitoringPlan.ruleID(fromDailyActivityName:)` / `ruleID(fromWarnActivityName:)` / `dayKey(fromActivityName:)`, `ScheduledDayPlanner.nextScheduledDayStart(after:days:calendar:)`, `RuleSnapshotUserDefaultsStore`, `UsageLedger.dayKey`, `DeviceActivityCenter`.
- Produces: no new app-target surface; a new private `reArmNextScheduledDay(forBlock:warn:endedDayKey:)` helper on the extension.

- [ ] **Step 1: Implement the self-arm in `intervalDidEnd` (build-verified)**

In `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`, extend `intervalDidEnd` so a block or warn activity that ended arms the next scheduled day and stops itself. Add the branch after the existing session/schedule/pause branches:

```swift
        else if MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue) != nil
                    || MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) != nil {
            reArmNextScheduledDay(endedActivity: activity.rawValue)
            DeviceActivityCenter().stopMonitoring([activity])
        }
```

Add the helper (device-only; mirrors `DeviceActivityCenterMonitor.startDayMonitoring`):

```swift
    /// A per-day block or warn activity ended at midnight: register the same
    /// activity kind for the rule's next scheduled day, so background enforcement
    /// continues without a foreground sync. Best-effort — the foreground N=2
    /// arming is the safety net. See the day-keyed enforcement spec §5.
    private func reArmNextScheduledDay(endedActivity name: String) {
        let isWarn = MonitoringPlan.ruleID(fromWarnActivityName: name) != nil
        guard
            let ruleID = isWarn
                ? MonitoringPlan.ruleID(fromWarnActivityName: name)
                : MonitoringPlan.ruleID(fromDailyActivityName: name),
            let endedKey = MonitoringPlan.dayKey(fromActivityName: name),
            let snapshot = RuleSnapshotUserDefaultsStore().snapshot(for: ruleID),
            snapshot.isEnabled, snapshot.kind == .timeLimit
        else { return }
        let calendar = Calendar.current
        // Anchor "after" on the ended interval's own day, parsed from its key, so a
        // late intervalDidEnd still advances to the correct next scheduled day.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let endedDay = formatter.date(from: endedKey),
              let nextStart = ScheduledDayPlanner.nextScheduledDayStart(
                after: endedDay, days: snapshot.days, calendar: calendar),
              let nextEnd = calendar.date(byAdding: .day, value: 1, to: nextStart)
        else { return }
        let nextKey = UsageLedger.dayKey(for: nextStart, calendar: calendar)
        let events: [String: Int]? = isWarn
            ? MonitoringPlan.warnEvent(forLimit: snapshot.dailyLimitMinutes)
            : MonitoringPlan.blockEvent(forLimit: snapshot.dailyLimitMinutes)
        guard let events else { return }
        let nextName = isWarn
            ? MonitoringPlan.warnActivityName(for: ruleID, dayKey: nextKey)
            : MonitoringPlan.dailyActivityName(for: ruleID, dayKey: nextKey)
        DeviceActivityCenterMonitor().armDayWindow(
            name: nextName, from: nextStart, to: nextEnd,
            selectionData: snapshot.selectionData, eventMinutes: events)
        Diag.log(.scheduler, .event, "self-arm \(nextName) (after \(endedKey))")
    }
```

Add a thin `armDayWindow` shim on `DeviceActivityCenterMonitor` (best-effort, swallows the throw with a log) so the monitor extension doesn't duplicate the schedule construction:

```swift
    /// Best-effort wrapper for the monitor's background self-arm: starts a dated
    /// event-carrying day window, logging instead of throwing.
    func armDayWindow(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) {
        do {
            try startDayMonitoring(
                name: name, from: start, to: end,
                selectionData: selectionData, eventMinutes: eventMinutes)
        } catch {
            Diag.error(.scheduler, "self-arm start failed \(name): \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 2: Run the planner test to confirm `nextScheduledDayStart` is green**

Xcode MCP `RunSomeTests` for `OpenAppLockTests/ScheduledDayPlannerTests/nextAfter`.
Expected: PASS (already implemented in Task 3 — this guards the logic the device path depends on).

- [ ] **Step 3: Build to verify the monitor compiles**

Xcode MCP `BuildProject` (scheme `OpenAppLock`, simulator destination).
Expected: build succeeds. The `startMonitoring` self-arm and full-day capture are **on-device verification items** (§14 of the spec / §11 device-only) — the simulator delivers no DeviceActivity callbacks.

- [ ] **Step 4: Commit**

```bash
git add OpenAppLockMonitor/DeviceActivityMonitorExtension.swift OpenAppLock/Services/RuleScheduler.swift
git commit -m "feat: self-arm the next scheduled per-day time-limit activity in the monitor

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Full-suite green, docs, and spec status

**Files:**
- Modify: doc comments on `Shared/Platform/MonitoringPlan.swift`, `OpenAppLock/Services/RuleScheduler.swift`, `Shared/Enforcement/LimitEnforcement.swift`, `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`
- Modify: `AGENTS.md` ("Rules feature map" row for DeviceActivity scheduling + "Known gaps")
- Modify: `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` (status note)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Run the full unit-test suite**

Xcode MCP `RunAllTests` (scheme `OpenAppLock`, simulator destination).
Expected: PASS. If `RuleSchedulerTests` / `NotificationSettingsUITests` flake under the full parallel run, re-run them in isolation before treating a failure as a regression (known flake; see project memory).

- [ ] **Step 2: Update owning doc comments**

Update the `///` doc comments to describe the per-day, day-keyed behavior:
- `MonitoringPlan` daily/warn name section — note the `-<dayKey>` suffix, the legacy un-keyed open-limit form, and `dayKey(fromActivityName:)`.
- `RuleScheduler.dayPlans` / `sync` — note the N=2 horizon and that time limits arm per-day while open limits keep the legacy repeating activity.
- `LimitEnforcement.handleUsageMinutes` — note the `activityDayKey` stale-flush drop as the primary guard, with the magnitude/confirmed-start guards retained as defense-in-depth.
- `DeviceActivityMonitorExtension.intervalDidEnd` — note the per-day self-arm.

- [ ] **Step 3: Update `AGENTS.md`**

- In the "Rules feature map" table, the "DeviceActivity scheduling, naming; background monitor" row already points at the right files; add a clause that time-limit enforcement is per-day day-keyed (`rule-<uuid>-<dayKey>` / `tlwarn-<uuid>-<dayKey>`).
- In "Known gaps / next steps", replace the stale "Scenario B false block corrected on foreground" framing under time-limit hardening with a pointer to `TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` and its device-verification items (self-arm, full-day capture, activity ceiling).

- [ ] **Step 4: Mark the spec status**

In `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md`, add a one-line status note under the title: implemented (unit-tested); device verification per §14 pending. Note it closes `TIME_LIMIT_COUNTING_HARDENING.md` §4d's Scenario B at the source.

- [ ] **Step 5: Manual UI validation**

Per AGENTS.md workflow, build and run the app on a simulator and confirm time-limit rules still create/edit/delete and the Usage section renders. Background day-keyed enforcement itself is device-only; state in the PR that the §14 on-device checks are handed to the maintainer (simulator delivers no DeviceActivity callbacks).

- [ ] **Step 6: Commit**

```bash
git add Shared/Platform/MonitoringPlan.swift OpenAppLock/Services/RuleScheduler.swift Shared/Enforcement/LimitEnforcement.swift OpenAppLockMonitor/DeviceActivityMonitorExtension.swift AGENTS.md Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md
git commit -m "docs: record day-keyed time-limit enforcement in source comments and AGENTS.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage**

- §3 per-day self-dating block + warn → Tasks 1–4 (naming, primitive, emission, drop).
- §4 naming/parsing (both prefixes, legacy-tolerant, `dayKey(fromActivityName:)`) → Task 1.
- §5 arming: foreground N=2 → Task 3; monitor self-arm → Task 5; reaping via declarative reconcile → Task 3 (`dayRolloverReapsPastActivity`).
- §6 drop (block + warn) + reset on block `intervalDidStart` (unchanged confirm/zero) → Task 4; the magnitude/confirmed-start guards retained → Task 4 Step 3.
- §7 open-limit keeps legacy repeating activity → Task 3 (`.openLimit` → `limitPlan`); schedule untouched.
- §8 migration (legacy reaped) → Task 1 parser recognizes legacy form + Task 3 reconcile reaping; (no data migration).
- §9 full-day capture / mid-day undercount → Task 3 arms at day-start; device-verified in Task 5/§14.
- §10 activity budget → emergent from Task 3 (N=2); no code, documented.
- §11 tests → Tasks 1–5 unit tests; device-only items called out in Task 5/Task 4 Step 6.
- §12 sequencing → Task order matches.
- §13/§14 risks/checklist → Task 6 docs + handoff.

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Each code step shows the code; modify-steps show the exact replacement region. The two device-only steps (Task 5 Step 1, Task 4 Step 5) show full code and are explicitly build-verified, not unit-tested — consistent with the spec's device-only classification.

**3. Type consistency:** `dailyActivityName(for:dayKey:)`/`warnActivityName(for:dayKey:)`, `dayKey(fromActivityName:)`, `ruleID(fromDailyActivityName:)`/`ruleID(fromWarnActivityName:)`, `Payload.day(from:to:selectionData:eventMinutes:)`, `startDayMonitoring(name:from:to:selectionData:eventMinutes:)`, `handleUsageMinutes(_:ruleID:activityDayKey:now:calendar:)`, `notifyIfEligible(ruleID:activityDayKey:now:calendar:)`, `ScheduledDayPlanner.upcomingScheduledDayStarts(days:from:count:calendar:)` / `nextScheduledDayStart(after:days:calendar:)`, `RuleScheduler.dayActivityHorizon`, `dayPlans(for:selectionData:at:calendar:)`, `MockActivityMonitor.startedDayWindows` — names are used identically across the tasks that define and consume them.

**Open item flagged for execution:** `sync(rules:at:)` currently uses `Calendar.current` internally. Tasks 3–4 thread `now` but rely on `.current` for the dayKey. If a test needs `utc` determinism for sync-level dayKeys, add a `calendar:` parameter to `sync` (and `dayPlans`) and pass `utc`; otherwise compute the expected dayKey with `.current` in the test, as written. Resolve this at Task 3 Step 5 based on whether the simulator's `.current` matches `utc` in CI (it does not — prefer adding the `calendar:` parameter).
