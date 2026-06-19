# Time-Limit Counting Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make time-limit enforcement robust against batched/late Screen Time threshold events — stop phantom blocks and under-counts, and provide an authoritative foreground usage total.

**Architecture:** Two complementary parts. Part A hardens the background path (record only for eligible rules; gate usage on a confirmed day-start) so stale cross-midnight flushes can't corrupt the ledger. Part B adds a `DeviceActivityReport` extension that computes the true daily total while the app is foreground and writes it to the app group; the app prefers that authoritative figure for display and the foreground block decision. See `Docs/Agents/Specs/TIME_LIMIT_COUNTING_HARDENING.md`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, FamilyControls / DeviceActivity / ManagedSettings (Screen Time), Swift Testing.

## Global Constraints

- **Tests:** Swift Testing (`import Testing`, `@Test`, `#expect`), `@MainActor` suites. Reuse `date()`, `utc`, `makeInMemoryContext()` from `OpenAppLockTests/TestSupport.swift`; create isolated `UserDefaults` per test (`UserDefaults(suiteName: "…-\(UUID())")!`).
- **Build & test:** via the Xcode MCP only (`BuildProject`, `RunSomeTests`, `RunAllTests`) on a **simulator** destination. Never invoke raw `xcodebuild`. `plutil -lint` is allowed for plist/pbxproj syntax checks (read-only).
- **Style:** value types, `let` over `var`, immutability; small focused files; no `print()` (use `os.Logger` if logging needed).
- **App group:** `group.dev.bchen.OpenAppLock`. **Report bundle id:** `dev.bchen.OpenAppLock.Report`. **Entitlements:** `com.apple.developer.family-controls` + the app group, on every extension.
- **Authoritative freshness window:** `120` seconds (named constant, tunable on device).
- **Commits:** Conventional Commits. End every commit message with:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TD4vdHbB8KqLPGYNbYNS5U
  ```
- **Branch:** `feat/time-limit-counting-hardening` (already created).

---

## Task A1: DayStartStore

**Files:**
- Create: `Shared/DayStartStore.swift`
- Test: `OpenAppLockTests/SchedulingTests.swift` (add a suite)

**Interfaces:**
- Produces: `final class DayStartStore { init(defaults: UserDefaults = AppGroup.defaults); func confirmedStart(for: UUID) -> Date?; func setConfirmedStart(_ : Date, for: UUID); func hasConfirmedStart(for: UUID, onDayContaining: Date, calendar: Calendar) -> Bool }`

- [ ] **Step 1: Write the failing test** — append to `OpenAppLockTests/SchedulingTests.swift`:

```swift
@MainActor
@Suite("Day-start store")
struct DayStartStoreTests {
    private func makeStore() -> DayStartStore {
        let name = "daystart-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return DayStartStore(defaults: defaults)
    }

    @Test("Confirmed start round-trips and is day-scoped")
    func roundTrip() {
        let store = makeStore()
        let id = UUID()
        let monday = date(2025, 1, 6, 10, 0)
        #expect(store.confirmedStart(for: id) == nil)
        #expect(!store.hasConfirmedStart(for: id, onDayContaining: monday, calendar: utc))

        store.setConfirmedStart(utc.startOfDay(for: monday), for: id)
        #expect(store.confirmedStart(for: id) == utc.startOfDay(for: monday))
        #expect(store.hasConfirmedStart(for: id, onDayContaining: monday, calendar: utc))
        // A different day is not confirmed.
        #expect(!store.hasConfirmedStart(for: id, onDayContaining: date(2025, 1, 7, 1, 0), calendar: utc))
    }
}
```

- [ ] **Step 2: Run test to verify it fails** — Xcode MCP `RunSomeTests` for `OpenAppLockTests/DayStartStoreTests`. Expected: FAIL (`DayStartStore` undefined / won't compile).

- [ ] **Step 3: Write minimal implementation** — create `Shared/DayStartStore.swift`:

```swift
//
//  DayStartStore.swift
//  OpenAppLock
//

import Foundation

/// Per-rule "last confirmed daily-activity start", written when the monitor's
/// `intervalDidStart` fires (and defensively by the foreground enforcer). Lets
/// limit enforcement reject usage checkpoints that arrive before today's
/// interval boundary has been observed — i.e. yesterday's batched threshold
/// events flushed late across midnight.
final class DayStartStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func confirmedStart(for ruleID: UUID) -> Date? {
        defaults.object(forKey: key(ruleID)) as? Date
    }

    func setConfirmedStart(_ dayStart: Date, for ruleID: UUID) {
        defaults.set(dayStart, forKey: key(ruleID))
    }

    /// Whether the confirmed start equals the start of the day containing `date`.
    func hasConfirmedStart(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current
    ) -> Bool {
        confirmedStart(for: ruleID) == calendar.startOfDay(for: date)
    }

    private func key(_ ruleID: UUID) -> String {
        "dayStart/\(ruleID.uuidString)"
    }
}
```

Then add `DayStartStore.swift` to the **OpenAppLock app** and **OpenAppLockMonitor** targets' membership (it is used by both). Mirror how `Shared/UsageLedger.swift` is referenced in `project.pbxproj` (add a `PBXFileReference` + `PBXBuildFile` entries in both targets' Sources phases).

- [ ] **Step 4: Run test to verify it passes** — `RunSomeTests` for `OpenAppLockTests/DayStartStoreTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/DayStartStore.swift OpenAppLock.xcodeproj/project.pbxproj OpenAppLockTests/SchedulingTests.swift
git commit  # message: "feat: add DayStartStore for confirmed daily-activity starts" + trailers
```

---

## Task A2: Record usage only for eligible rules (4a)

**Files:**
- Modify: `Shared/LimitEnforcement.swift` (`handleUsageMinutes`, lines ~47–71)
- Test: `OpenAppLockTests/SchedulingTests.swift` (`LimitEnforcementTests` suite)

**Interfaces:**
- Consumes: existing `LimitEnforcement`, `MockShieldController`, `snapshot(...)` helper.
- Produces: no signature change.

- [ ] **Step 1: Write the failing test** — in `LimitEnforcementTests`, first extend the `snapshot` helper to take days, then add a test.

Change the helper signature from:
```swift
    private func snapshot(
        kind: RuleKind, limit: Int = 45, maxOpens: Int = 5, pausedUntil: Date? = nil
    ) -> RuleSnapshot {
```
to add a `days` parameter:
```swift
    private func snapshot(
        kind: RuleKind, limit: Int = 45, maxOpens: Int = 5,
        days: Set<Weekday> = Weekday.everyDay, pausedUntil: Date? = nil
    ) -> RuleSnapshot {
```
and use `dayNumbers: days.map(\.rawValue)` in the returned `RuleSnapshot` (replacing `Weekday.everyDay.map(\.rawValue)`).

Add the test:
```swift
    @Test("An ineligible rule does not accrue usage from a checkpoint")
    func ineligibleRuleDoesNotAccrue() {
        let (enforcement, _, ledger, store) = makeEnforcement()
        // Weekday-only rule; a checkpoint arrives on a Saturday (not scheduled).
        let snap = snapshot(kind: .timeLimit, days: Weekday.weekdays)
        store.save([snap])
        let saturday = date(2025, 1, 11, 10, 0) // 2025-01-11 is a Saturday

        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: saturday, calendar: utc)

        #expect(
            ledger.usage(for: snap.id, onDayContaining: saturday, calendar: utc).minutesUsed == 0)
    }
```

- [ ] **Step 2: Run test to verify it fails** — `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`. Expected: FAIL — `ineligibleRuleDoesNotAccrue` records 20 because `recordMinutesUsed` runs before the eligibility guard.

- [ ] **Step 3: Write minimal implementation** — in `Shared/LimitEnforcement.swift`, reorder `handleUsageMinutes` so the record happens after eligibility. Replace the body after the magnitude guard:

```swift
        let minutesSinceMidnight = Int(
            now.timeIntervalSince(calendar.startOfDay(for: now)) / 60)
        guard minutes <= minutesSinceMidnight else { return }

        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              snapshot.kind == .timeLimit,
              !snapshot.isPaused(at: now),
              snapshot.isScheduledToday(at: now, calendar: calendar)
        else { return }
        ledger.recordMinutesUsed(minutes, for: ruleID, onDayContaining: now, calendar: calendar)
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        if snapshot.limitReached(given: usage) {
            shield(snapshot)
        }
```

- [ ] **Step 4: Run test to verify it passes** — `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`. Expected: PASS (all, including the pre-existing checkpoint tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/LimitEnforcement.swift OpenAppLockTests/SchedulingTests.swift
git commit  # "fix: record time-limit usage only for rules eligible today" + trailers
```

---

## Task A3: Confirmed day-start gate + zero-once (4b)

**Files:**
- Modify: `Shared/LimitEnforcement.swift` (add `dayStarts` member; `handleDayStart`; gate in `handleUsageMinutes`)
- Test: `OpenAppLockTests/SchedulingTests.swift` (`LimitEnforcementTests`)

**Interfaces:**
- Consumes: `DayStartStore` (A1).
- Produces: `LimitEnforcement` gains member `var dayStarts = DayStartStore()`.

- [ ] **Step 1: Write the failing tests.**

First, update `makeEnforcement()` to inject an isolated `DayStartStore`:
```swift
    private func makeEnforcement() -> (LimitEnforcement, MockShieldController, UsageLedger, RuleSnapshotStore) {
        let shields = MockShieldController()
        let ledger = UsageLedger(defaults: freshDefaults())
        let store = RuleSnapshotStore(defaults: freshDefaults())
        return (
            LimitEnforcement(
                snapshots: store, ledger: ledger, shields: shields,
                sessions: OpenSessionStore(defaults: freshDefaults()),
                dayStarts: DayStartStore(defaults: freshDefaults())),
            shields, ledger, store)
    }
```

Next, the three existing checkpoint tests must establish a confirmed day-start first (the gate now requires it). Update them:

In `usageCheckpointsShieldAtLimit`, insert after `store.save([snap])`:
```swift
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
```
In `staleCrossMidnightCheckpointIgnored`, insert after `store.save([snap])`:
```swift
        enforcement.handleDayStart(ruleID: snap.id, now: earlyMorning, calendar: utc)
```
In `freshCheckpointWithinElapsedHonoured`, insert after `store.save([snap])`:
```swift
        enforcement.handleDayStart(ruleID: snap.id, now: quarterToOne, calendar: utc)
```

Then add new tests:
```swift
    @Test("A checkpoint before a confirmed day-start is dropped")
    func checkpointBeforeConfirmedStartDropped() {
        let (enforcement, shields, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit, limit: 45)
        store.save([snap])
        // No handleDayStart → no confirmed start for today.
        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: monday, calendar: utc)

        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 0)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Day start zeroes today's time-limit ledger once, only on a transition")
    func dayStartZeroesOnceOnTransition() {
        let (enforcement, _, ledger, store) = makeEnforcement()
        let snap = snapshot(kind: .timeLimit)
        store.save([snap])
        // A stale value sitting in today's key (e.g. a pre-boundary write).
        ledger.setUsage(
            RuleUsage(minutesUsed: 45), for: snap.id, onDayContaining: monday, calendar: utc)

        // First day-start: transition → zeroed.
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 0)

        // A legitimate accrual after the transition...
        enforcement.handleUsageMinutes(20, ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 20)

        // ...survives a spurious same-day re-fire (no second zero).
        enforcement.handleDayStart(ruleID: snap.id, now: monday, calendar: utc)
        #expect(ledger.usage(for: snap.id, onDayContaining: monday, calendar: utc).minutesUsed == 20)
    }
```

- [ ] **Step 2: Run tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`. Expected: FAIL to compile (`dayStarts:` arg doesn't exist yet) and/or new tests fail.

- [ ] **Step 3: Write minimal implementation** — in `Shared/LimitEnforcement.swift`:

Add the member after `var sessions = OpenSessionStore()`:
```swift
    /// Confirmed daily-activity starts, used to reject pre-boundary stale flushes.
    var dayStarts = DayStartStore()
```

Replace `handleDayStart` with:
```swift
    func handleDayStart(ruleID: UUID, now: Date = .now, calendar: Calendar = .current) {
        guard let snapshot = snapshots.snapshot(for: ruleID), snapshot.isEnabled,
              !snapshot.isPaused(at: now)
        else { return }
        confirmDayStart(ruleID: ruleID, kind: snapshot.kind, now: now, calendar: calendar)
        let usage = ledger.usage(for: ruleID, onDayContaining: now, calendar: calendar)
        switch snapshot.kind {
        case .schedule:
            break
        case .openLimit:
            if snapshot.isScheduledToday(at: now, calendar: calendar) {
                shield(snapshot)
            } else {
                shields.clearShield(ruleID: ruleID)
            }
        case .timeLimit:
            if snapshot.limitReached(given: usage, at: now),
               snapshot.isScheduledToday(at: now, calendar: calendar) {
                shield(snapshot)
            } else {
                shields.clearShield(ruleID: ruleID)
            }
        }
    }

    /// Records today as the confirmed interval start for `ruleID`. On a genuine
    /// new-day transition for a time-limit rule, zeroes today's ledger once so a
    /// stale pre-boundary checkpoint cannot survive; a spurious same-day re-fire
    /// must not erase legitimate usage.
    private func confirmDayStart(
        ruleID: UUID, kind: RuleKind, now: Date, calendar: Calendar
    ) {
        let today = calendar.startOfDay(for: now)
        guard dayStarts.confirmedStart(for: ruleID) != today else { return }
        dayStarts.setConfirmedStart(today, for: ruleID)
        if kind == .timeLimit {
            ledger.setUsage(RuleUsage(), for: ruleID, onDayContaining: now, calendar: calendar)
        }
    }
```
(Note: `limitReached(given:at:)` gets its `at:` parameter in Task B4; until then call it as `limitReached(given: usage)`. If executing strictly in order, write `snapshot.limitReached(given: usage)` here and add `at: now` in B4.)

Add the gate to `handleUsageMinutes`, immediately after the magnitude guard:
```swift
        guard minutes <= minutesSinceMidnight else { return }
        // Reject events that arrive before today's interval boundary has been
        // observed — yesterday's batched checkpoints flushed across midnight.
        guard dayStarts.hasConfirmedStart(for: ruleID, onDayContaining: now, calendar: calendar)
        else { return }
```

- [ ] **Step 4: Run tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/LimitEnforcementTests`. Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add Shared/LimitEnforcement.swift OpenAppLockTests/SchedulingTests.swift
git commit  # "fix: gate time-limit usage on a confirmed day-start" + trailers
```

---

## Task A4: Foreground safety net (4c)

**Files:**
- Modify: `OpenAppLock/Services/RuleEnforcer.swift` (init + `refresh`)
- Test: `OpenAppLockTests/RuleEnforcerTests.swift`

**Interfaces:**
- Consumes: `DayStartStore` (A1).
- Produces: `RuleEnforcer.init(..., dayStarts: DayStartStore = DayStartStore())`.

- [ ] **Step 1: Write the failing test** — add to `RuleEnforcerTests`:

```swift
    @Test("Refresh establishes today's confirmed day-start for a time-limit rule")
    func refreshEstablishesConfirmedStart() {
        let shields = MockShieldController()
        let suite = "enforcer-daystart-\(UUID().uuidString)"
        let dayStarts = DayStartStore(defaults: UserDefaults(suiteName: suite)!)
        let enforcer = RuleEnforcer(shields: shields, dayStarts: dayStarts)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig()), days: Weekday.everyDay)

        #expect(dayStarts.confirmedStart(for: rule.id) == nil)
        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(dayStarts.confirmedStart(for: rule.id) == utc.startOfDay(for: mondayDuringWork))
    }
```

- [ ] **Step 2: Run test to verify it fails** — `RunSomeTests` for `OpenAppLockTests/RuleEnforcerTests`. Expected: FAIL to compile (`dayStarts:` arg doesn't exist).

- [ ] **Step 3: Write minimal implementation** — in `OpenAppLock/Services/RuleEnforcer.swift`:

Add a stored property and init parameter:
```swift
    private let dayStarts: DayStartStore
```
In `init`, add `dayStarts: DayStartStore = DayStartStore()` as the last parameter and assign `self.dayStarts = dayStarts`.

In `refresh`, inside the `for rule in rules` loop, after the pause-expiry block and before computing `usage`:
```swift
            // 4c safety net: a skipped monitor `intervalDidStart` would block
            // usage recording all day; establish today's confirmed start from
            // the foreground (no zeroing — preserve any legitimate accrual).
            if rule.kind == .timeLimit, rule.isEnabled,
               dayStarts.confirmedStart(for: rule.id) != calendar.startOfDay(for: now) {
                dayStarts.setConfirmedStart(calendar.startOfDay(for: now), for: rule.id)
            }
```

- [ ] **Step 4: Run test to verify it passes** — `RunSomeTests` for `OpenAppLockTests/RuleEnforcerTests`. Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Services/RuleEnforcer.swift OpenAppLockTests/RuleEnforcerTests.swift
git commit  # "feat: establish confirmed day-start from the foreground enforcer" + trailers
```

---

## Task B1: Collapse the threshold chain to one block event (5a)

**Files:**
- Modify: `Shared/MonitoringPlan.swift` (`minuteEvents(forLimit:)` → `blockEvent(forLimit:)`)
- Modify: `OpenAppLock/Services/RuleScheduler.swift` (call site, ~line 70)
- Test: `OpenAppLockTests/SchedulingTests.swift` (`MonitoringPlanTests`, `RuleSchedulerTests`)

**Interfaces:**
- Produces: `static func blockEvent(forLimit limitMinutes: Int) -> [String: Int]` (one entry).

- [ ] **Step 1: Write the failing tests.**

Replace `MonitoringPlanTests.minuteEvents` with:
```swift
    @Test("A time limit registers a single block event at the budget")
    func blockEvent() {
        let events = MonitoringPlan.blockEvent(forLimit: 45)
        #expect(events.count == 1)
        #expect(events[MonitoringPlan.minuteEventName(for: 45)] == 45)
        #expect(
            MonitoringPlan.minutes(fromEventName: MonitoringPlan.minuteEventName(for: 45)) == 45)
        #expect(MonitoringPlan.minutes(fromEventName: "nope") == nil)
    }
```

In `RuleSchedulerTests.startsMonitoring`, change:
```swift
        #expect(monitor.startedEvents[name]?.count == rule.dailyLimitMinutes)
```
to:
```swift
        #expect(monitor.startedEvents[name]?.count == 1)
        #expect(monitor.startedEvents[name]?[MonitoringPlan.minuteEventName(for: rule.dailyLimitMinutes)] == rule.dailyLimitMinutes)
```

- [ ] **Step 2: Run tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/MonitoringPlanTests` and `OpenAppLockTests/RuleSchedulerTests`. Expected: FAIL (`blockEvent` undefined).

- [ ] **Step 3: Write minimal implementation.**

In `Shared/MonitoringPlan.swift`, replace `minuteEvents(forLimit:)` with:
```swift
    /// The single cumulative-usage checkpoint for a time-limit rule: one event
    /// at the budget, used by the monitor as the background block trigger. Live
    /// sub-budget progress comes from the DeviceActivityReport extension, not a
    /// per-minute chain (Screen Time batches sub-budget thresholds unreliably).
    static func blockEvent(forLimit limitMinutes: Int) -> [String: Int] {
        let minutes = max(1, limitMinutes)
        return [minuteEventName(for: minutes): minutes]
    }
```

In `OpenAppLock/Services/RuleScheduler.swift`, change:
```swift
                let events =
                    rule.kind == .timeLimit
                    ? MonitoringPlan.minuteEvents(forLimit: rule.dailyLimitMinutes)
                    : [:]
```
to:
```swift
                let events =
                    rule.kind == .timeLimit
                    ? MonitoringPlan.blockEvent(forLimit: rule.dailyLimitMinutes)
                    : [:]
```

- [ ] **Step 4: Run tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/MonitoringPlanTests` and `OpenAppLockTests/RuleSchedulerTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/MonitoringPlan.swift OpenAppLock/Services/RuleScheduler.swift OpenAppLockTests/SchedulingTests.swift
git commit  # "feat: collapse time-limit threshold chain to a single block event" + trailers
```

---

## Task B2: Authoritative usage fields + effective resolver (5b)

**Files:**
- Modify: `Shared/UsageLedger.swift` (`RuleUsage`)
- Test: `OpenAppLockTests/UsageTests.swift` (`UsageLedgerTests`)

**Interfaces:**
- Produces: `RuleUsage.authoritativeMinutesUsed: Int?`, `RuleUsage.authoritativeAsOf: Date?`, `static RuleUsage.authoritativeFreshness: TimeInterval`, `func effectiveMinutesUsed(asOf: Date, freshness: TimeInterval) -> Int`.

- [ ] **Step 1: Write the failing tests** — add to `UsageLedgerTests`:

```swift
    @Test("Effective minutes prefer a fresh authoritative reading, else fall back")
    func effectiveMinutes() {
        let now = date(2025, 1, 6, 10, 0)
        var usage = RuleUsage(minutesUsed: 12)
        // No authoritative reading → threshold count.
        #expect(usage.effectiveMinutesUsed(asOf: now) == 12)
        // Fresh authoritative → wins.
        usage.authoritativeMinutesUsed = 20
        usage.authoritativeAsOf = now.addingTimeInterval(-30)
        #expect(usage.effectiveMinutesUsed(asOf: now) == 20)
        // Stale authoritative → threshold fallback.
        usage.authoritativeAsOf = now.addingTimeInterval(-600)
        #expect(usage.effectiveMinutesUsed(asOf: now) == 12)
    }

    @Test("Usage round-trips authoritative fields and decodes legacy blobs")
    func authoritativeCodable() throws {
        var usage = RuleUsage(minutesUsed: 5, opensUsed: 2)
        usage.authoritativeMinutesUsed = 30
        usage.authoritativeAsOf = date(2025, 1, 6, 10, 0)
        let data = try JSONEncoder().encode(usage)
        #expect(try JSONDecoder().decode(RuleUsage.self, from: data) == usage)

        // A blob written before the authoritative fields existed still decodes.
        let legacy = Data(#"{"minutesUsed":7,"opensUsed":1}"#.utf8)
        let decoded = try JSONDecoder().decode(RuleUsage.self, from: legacy)
        #expect(decoded.minutesUsed == 7)
        #expect(decoded.authoritativeMinutesUsed == nil)
        #expect(decoded.authoritativeAsOf == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/UsageLedgerTests`. Expected: FAIL (no such members).

- [ ] **Step 3: Write minimal implementation** — in `Shared/UsageLedger.swift`, replace the `RuleUsage` struct:

```swift
struct RuleUsage: Codable, Equatable {
    var minutesUsed = 0
    var opensUsed = 0
    /// The true daily total written by the DeviceActivityReport extension while
    /// the app is foreground; preferred over `minutesUsed` when fresh.
    var authoritativeMinutesUsed: Int?
    /// When the authoritative total was computed.
    var authoritativeAsOf: Date?

    /// How long an authoritative reading is trusted before falling back to the
    /// threshold count. Tunable on device.
    static let authoritativeFreshness: TimeInterval = 120

    /// The daily minutes to use for display and the block decision: the report's
    /// authoritative total when fresh, else the threshold count.
    func effectiveMinutesUsed(
        asOf now: Date, freshness: TimeInterval = RuleUsage.authoritativeFreshness
    ) -> Int {
        if let authoritative = authoritativeMinutesUsed, let asOf = authoritativeAsOf,
           abs(now.timeIntervalSince(asOf)) <= freshness {
            return authoritative
        }
        return minutesUsed
    }
}
```
(Optional properties get an implicit `nil` default, so the existing memberwise calls `RuleUsage(minutesUsed:)` / `RuleUsage(minutesUsed:opensUsed:)` keep compiling, and synthesized `Decodable` treats them as `decodeIfPresent` so legacy blobs decode.)

- [ ] **Step 4: Run tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/UsageLedgerTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/UsageLedger.swift OpenAppLockTests/UsageTests.swift
git commit  # "feat: add authoritative usage fields and effective-minutes resolver" + trailers
```

---

## Task B3: UsageLedger.recordAuthoritativeMinutes (5b)

**Files:**
- Modify: `Shared/UsageLedger.swift` (add method)
- Test: `OpenAppLockTests/UsageTests.swift` (`UsageLedgerTests`)

**Interfaces:**
- Produces: `func recordAuthoritativeMinutes(_ minutes: Int, for: UUID, onDayContaining: Date, asOf: Date, calendar: Calendar)`.

- [ ] **Step 1: Write the failing test** — add to `UsageLedgerTests`:

```swift
    @Test("Authoritative minutes overwrite without disturbing the threshold count")
    func recordAuthoritative() {
        let ledger = makeLedger()
        let id = UUID()
        ledger.recordMinutesUsed(40, for: id, onDayContaining: monday, calendar: utc)

        ledger.recordAuthoritativeMinutes(
            12, for: id, onDayContaining: monday, asOf: monday, calendar: utc)
        let read = ledger.usage(for: id, onDayContaining: monday, calendar: utc)
        #expect(read.minutesUsed == 40)               // threshold untouched
        #expect(read.authoritativeMinutesUsed == 12)  // authoritative recorded
        #expect(read.authoritativeAsOf == monday)
        // Effective prefers the (fresh) authoritative figure.
        #expect(read.effectiveMinutesUsed(asOf: monday) == 12)
    }
```

- [ ] **Step 2: Run test to verify it fails** — `RunSomeTests` for `OpenAppLockTests/UsageLedgerTests`. Expected: FAIL (no such method).

- [ ] **Step 3: Write minimal implementation** — in `Shared/UsageLedger.swift`, add to `UsageLedger` (after `recordMinutesUsed`):

```swift
    /// Records the report's authoritative daily total without disturbing the
    /// monotonic threshold count.
    func recordAuthoritativeMinutes(
        _ minutes: Int, for ruleID: UUID, onDayContaining date: Date, asOf: Date,
        calendar: Calendar = .current
    ) {
        var usage = self.usage(for: ruleID, onDayContaining: date, calendar: calendar)
        usage.authoritativeMinutesUsed = minutes
        usage.authoritativeAsOf = asOf
        setUsage(usage, for: ruleID, onDayContaining: date, calendar: calendar)
    }
```

- [ ] **Step 4: Run test to verify it passes** — `RunSomeTests` for `OpenAppLockTests/UsageLedgerTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/UsageLedger.swift OpenAppLockTests/UsageTests.swift
git commit  # "feat: record authoritative usage minutes in the ledger" + trailers
```

---

## Task B4: limitReached uses effective minutes (5c)

**Files:**
- Modify: `OpenAppLock/Logic/RuleStatus.swift` (`BlockingRule.limitReached`, `status`)
- Modify: `Shared/RuleSnapshot.swift` (`RuleSnapshot.limitReached`)
- Modify: `Shared/LimitEnforcement.swift` (3 call sites pass `now`)
- Modify: `Shared/UninstallProtectionPolicy.swift` (1 call site passes `now`)
- Test: `OpenAppLockTests/UsageTests.swift` (`UsageStatusTests`, `UsageEnforcementTests`)

**Interfaces:**
- Produces: `limitReached(given: RuleUsage, at now: Date = .now) -> Bool` on both `BlockingRule` and `RuleSnapshot`.

- [ ] **Step 1: Write the failing tests** — add to `UsageStatusTests`:

```swift
    @Test("A fresh authoritative reading below budget keeps a rule inactive")
    func freshAuthoritativeBelowBudgetInactive() {
        let rule = timeLimitRule(limit: 45)
        var usage = RuleUsage(minutesUsed: 45)        // threshold says spent (phantom)
        usage.authoritativeMinutesUsed = 5            // report says 5
        usage.authoritativeAsOf = mondayMorning.addingTimeInterval(-10)
        #expect(!rule.status(at: mondayMorning, calendar: utc, usage: usage).isActive)
    }

    @Test("A fresh authoritative reading at budget blocks even if threshold lags")
    func freshAuthoritativeAtBudgetBlocks() {
        let rule = timeLimitRule(limit: 45)
        var usage = RuleUsage(minutesUsed: 10)
        usage.authoritativeMinutesUsed = 45
        usage.authoritativeAsOf = mondayMorning.addingTimeInterval(-10)
        #expect(
            rule.status(at: mondayMorning, calendar: utc, usage: usage)
                == .active(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("A stale authoritative reading falls back to the threshold count")
    func staleAuthoritativeUsesThreshold() {
        let rule = timeLimitRule(limit: 45)
        var usage = RuleUsage(minutesUsed: 45)
        usage.authoritativeMinutesUsed = 5
        usage.authoritativeAsOf = mondayMorning.addingTimeInterval(-600) // stale
        #expect(rule.status(at: mondayMorning, calendar: utc, usage: usage).isActive)
    }
```

Add to `UsageEnforcementTests`:
```swift
    @Test("A fresh authoritative reading below budget clears a phantom block")
    func freshAuthoritativeClearsPhantomBlock() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        var usage = RuleUsage(minutesUsed: 45)       // threshold phantom
        usage.authoritativeMinutesUsed = 5
        usage.authoritativeAsOf = mondayMorning.addingTimeInterval(-10)
        ledger.usageByRule[rule.id] = usage

        enforcer.refresh(rules: [rule], at: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)     // authoritative wins → not blocked
    }
```

- [ ] **Step 2: Run tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/UsageStatusTests` and `OpenAppLockTests/UsageEnforcementTests`. Expected: FAIL (status uses raw `minutesUsed`).

- [ ] **Step 3: Write minimal implementation.**

In `OpenAppLock/Logic/RuleStatus.swift`, change `limitReached`:
```swift
    func limitReached(given usage: RuleUsage, at now: Date = .now) -> Bool {
        switch configuration {
        case .schedule: false
        case .timeLimit(let config): usage.effectiveMinutesUsed(asOf: now) >= config.dailyLimitMinutes
        case .openLimit(let config): usage.opensUsed >= config.maxOpens
        }
    }
```
In the same file, in `status(...)`, change the limit branch call from `limitReached(given: usage)` to `limitReached(given: usage, at: now)`.

In `Shared/RuleSnapshot.swift`, change `limitReached`:
```swift
    func limitReached(given usage: RuleUsage, at now: Date = .now) -> Bool {
        switch kind {
        case .schedule: false
        case .timeLimit: usage.effectiveMinutesUsed(asOf: now) >= dailyLimitMinutes
        case .openLimit: usage.opensUsed >= maxOpens
        }
    }
```

In `Shared/LimitEnforcement.swift`, pass `now` at the three `snapshot.limitReached(given: usage)` calls (in `handleDayStart`, `handleUsageMinutes`, `handleOpenRequest`): `snapshot.limitReached(given: usage, at: now)`.

In `Shared/UninstallProtectionPolicy.swift` line ~61, change `snapshot.limitReached(given: usage)` to `snapshot.limitReached(given: usage, at: now)`.

- [ ] **Step 4: Run the full suite to verify pass + no regressions** — `RunSomeTests` for `OpenAppLockTests/UsageStatusTests`, `OpenAppLockTests/UsageEnforcementTests`, `OpenAppLockTests/LimitEnforcementTests`, `OpenAppLockTests/UninstallProtectionEnforcerTests`. Expected: PASS (all).

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Logic/RuleStatus.swift Shared/RuleSnapshot.swift Shared/LimitEnforcement.swift Shared/UninstallProtectionPolicy.swift OpenAppLockTests/UsageTests.swift
git commit  # "feat: use effective (authoritative-aware) minutes in limitReached" + trailers
```

---

## Task B5: Usage display uses effective minutes (5c)

**Files:**
- Modify: `OpenAppLock/Logic/UsageDisplay.swift` (`usagePhrase`)
- Modify: `OpenAppLock/Logic/RuleStatus.swift` (`rowContext` passes `now` to `usagePhrase`)
- Test: `OpenAppLockTests/UsageTests.swift` (`UsageDisplayTests`)

**Interfaces:**
- Produces: `UsageDisplay.usagePhrase(for: BlockingRule, usage: RuleUsage, asOf now: Date) -> String`.

- [ ] **Step 1: Write the failing tests.**

Update the three direct callers in `UsageDisplayTests` to pass `asOf: now`:
```swift
        #expect(UsageDisplay.usagePhrase(for: timeRule, usage: usage, asOf: now) == "18m of 45m used")
```
(in `timeLimitStrings`), 
```swift
        #expect(UsageDisplay.usagePhrase(for: openRule, usage: usage, asOf: now) == "2 of 5 opens")
```
(in `openLimitStrings`), and
```swift
        #expect(UsageDisplay.usagePhrase(for: timeRule, usage: over, asOf: now) == "45m of 45m used")
```
(in `overshootClamps`).

Add a new test:
```swift
    @Test("Usage phrase reflects a fresh authoritative reading")
    func usagePhrasePrefersFreshAuthoritative() {
        var usage = RuleUsage(minutesUsed: 5)
        usage.authoritativeMinutesUsed = 18
        usage.authoritativeAsOf = now.addingTimeInterval(-10)
        #expect(UsageDisplay.usagePhrase(for: timeRule, usage: usage, asOf: now) == "18m of 45m used")
    }
```

- [ ] **Step 2: Run tests to verify they fail** — `RunSomeTests` for `OpenAppLockTests/UsageDisplayTests`. Expected: FAIL (signature mismatch).

- [ ] **Step 3: Write minimal implementation.**

In `OpenAppLock/Logic/UsageDisplay.swift`, change `usagePhrase`:
```swift
    static func usagePhrase(for rule: BlockingRule, usage: RuleUsage, asOf now: Date) -> String {
        switch rule.configuration {
        case .schedule:
            ""
        case .timeLimit(let config):
            "\(min(usage.effectiveMinutesUsed(asOf: now), config.dailyLimitMinutes))m of "
                + "\(config.dailyLimitMinutes)m used"
        case .openLimit(let config):
            "\(min(usage.opensUsed, config.maxOpens)) of \(config.maxOpens) opens"
        }
    }
```

In `OpenAppLock/Logic/RuleStatus.swift`, in `rowContext`, change:
```swift
                    ? UsageDisplay.usagePhrase(for: self, usage: usage)
```
to:
```swift
                    ? UsageDisplay.usagePhrase(for: self, usage: usage, asOf: now)
```

- [ ] **Step 4: Run tests to verify they pass** — `RunSomeTests` for `OpenAppLockTests/UsageDisplayTests`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Logic/UsageDisplay.swift OpenAppLock/Logic/RuleStatus.swift OpenAppLockTests/UsageTests.swift
git commit  # "feat: show effective (authoritative-aware) minutes in usage strings" + trailers
```

---

## Task B5.5: Full regression checkpoint

- [ ] **Step 1: Run the whole unit suite** — Xcode MCP `RunAllTests` (or `RunSomeTests` for `OpenAppLockTests`). Expected: PASS for every suite. Fix any regression before proceeding to the device-only tasks. No commit (verification only).

---

## Task B6: OpenAppLockReport extension target (pbxproj hand-edit) — device-only

> Cannot be unit-tested. The gate is: the project opens, `plutil -lint` passes, and the app + all four extensions build via the Xcode MCP.

**Files:**
- Create: `OpenAppLockReport/Info.plist`
- Create: `OpenAppLockReport/OpenAppLockReport.entitlements`
- Modify: `OpenAppLock.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the Info.plist** — `OpenAppLockReport/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSExtension</key>
	<dict>
		<key>NSExtensionPointIdentifier</key>
		<string>com.apple.deviceactivity.report-extension</string>
	</dict>
</dict>
</plist>
```

- [ ] **Step 2: Create the entitlements** — `OpenAppLockReport/OpenAppLockReport.entitlements` (identical to `OpenAppLockMonitor.entitlements`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.family-controls</key>
	<true/>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.dev.bchen.OpenAppLock</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 3: Add the target to project.pbxproj** — read the file and replicate every `OpenAppLockMonitor` object for a new `OpenAppLockReport` target, with fresh unique 24-hex IDs (the existing extensions use a synthetic `E40000000000000000000001`–`0003` scheme for their build-configuration lists; continue with `…0004` for the report's list and unique hex for the rest). Specifically duplicate and adapt:
  - the `PBXNativeTarget` (productType `com.apple.product-type.app-extension`), its three build phases (Sources, Frameworks, Resources), and its `buildConfigurationList`;
  - the `XCBuildConfiguration` Debug + Release, setting `PRODUCT_BUNDLE_IDENTIFIER = dev.bchen.OpenAppLock.Report`, `INFOPLIST_FILE = OpenAppLockReport/Info.plist`, `CODE_SIGN_ENTITLEMENTS = OpenAppLockReport/OpenAppLockReport.entitlements`, same `IPHONEOS_DEPLOYMENT_TARGET`/team/`SWIFT_VERSION`/`GENERATE_INFOPLIST_FILE` settings as the monitor, and `INFOPLIST_KEY_CFBundleDisplayName = OpenAppLockReport`;
  - the `.appex` `PBXFileReference` (product) and the group entries for the `OpenAppLockReport/` folder + its files;
  - a `PBXBuildFile` + `PBXTargetDependency` so the app target **embeds** the new `.appex` (add it to the app's existing "Embed App Extensions"/Copy Files (Plug-ins) phase and to `dependencies`).
  - the **Sources** build phase must list the report's own Swift files (Task B7) **and** the Shared files they need: `AppGroup.swift`, `RuleKind.swift`, `Weekday.swift`, `RuleSchedule.swift`, `RuleConfiguration.swift`, `RuleSnapshot.swift`, `UsageLedger.swift`, `ShieldController.swift` (for `AppSelectionCodec`), `DeviceActivityReportContext.swift`. (Mirror the Shared files already in the monitor target, plus these.)

- [ ] **Step 4: Lint the project file** — Run: `plutil -lint OpenAppLock.xcodeproj/project.pbxproj`. Expected: `OK`. If not, the edit is malformed — fix before building.

- [ ] **Step 5: Build** — Xcode MCP `BuildProject` (simulator destination). Expected: build **fails** with "missing file/symbol" only if Task B7 files don't exist yet — that is acceptable here; the gate for this task is that the project parses and the new target appears. If the report Swift files already exist, expect a clean build. (Practical ordering: do B7's file creation, then return here to build green.)

- [ ] **Step 6: Commit**

```bash
git add OpenAppLockReport/Info.plist OpenAppLockReport/OpenAppLockReport.entitlements OpenAppLock.xcodeproj/project.pbxproj
git commit  # "build: add OpenAppLockReport DeviceActivityReport extension target" + trailers
```

---

## Task B7: Report extension code + host report view (5d) — device-only

> Cannot be unit-tested (the simulator delivers no DeviceActivity data and does not render report extensions). Gate: the app + all four extensions build via the Xcode MCP.

**Files:**
- Create: `Shared/DeviceActivityReportContext.swift`
- Create: `OpenAppLockReport/OpenAppLockReport.swift`
- Create: `OpenAppLockReport/RuleUsageReport.swift`
- Create: `OpenAppLockReport/RuleUsageReportWriter.swift`
- Modify: `OpenAppLock/Views/MainView.swift`
- Modify: `OpenAppLock.xcodeproj/project.pbxproj` (add the three report Swift files + `DeviceActivityReportContext.swift` to the report target; add `DeviceActivityReportContext.swift` to the app target)

- [ ] **Step 1: Shared context** — `Shared/DeviceActivityReportContext.swift`:

```swift
//
//  DeviceActivityReportContext.swift
//  OpenAppLock
//

import DeviceActivity

extension DeviceActivityReport.Context {
    /// The report scene that recomputes authoritative daily usage for limit rules.
    static let ruleUsage = Self("Rule Usage")
}
```

- [ ] **Step 2: Writer** — `OpenAppLockReport/RuleUsageReportWriter.swift`:

```swift
//
//  RuleUsageReportWriter.swift
//  OpenAppLockReport
//

import DeviceActivity
import FamilyControls
import Foundation

/// Sums each enabled time-limit rule's true daily usage from Screen Time's own
/// totals and records it as the authoritative figure in the shared ledger.
struct RuleUsageReportWriter {
    func write(from data: DeviceActivityResults<DeviceActivityData>, now: Date = Date()) async {
        let snapshots = RuleSnapshotStore().load()
            .filter { $0.kind == .timeLimit && $0.isEnabled }
        guard !snapshots.isEmpty else { return }
        let selections = snapshots.map { ($0, AppSelectionCodec.decode($0.selectionData)) }

        var secondsByRule: [UUID: Double] = [:]
        for await segment in data.flatMap({ $0.activitySegments }) {
            for await category in segment.categories {
                for await app in category.applications {
                    guard let token = app.application.token else { continue }
                    let seconds = app.totalActivityDuration
                    for (snap, selection) in selections
                    where selection.applicationTokens.contains(token) {
                        secondsByRule[snap.id, default: 0] += seconds
                    }
                }
            }
        }

        let ledger = UsageLedger()
        for (snap, _) in selections {
            let minutes = Int((secondsByRule[snap.id] ?? 0) / 60)
            ledger.recordAuthoritativeMinutes(
                minutes, for: snap.id, onDayContaining: now, asOf: now)
        }
    }
}
```
(Note: category/web-domain selections are not attributed yet — applications only; confirm coverage on device, see spec §9.)

- [ ] **Step 3: Scene** — `OpenAppLockReport/RuleUsageReport.swift`:

```swift
//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Recomputes authoritative daily usage for time-limit rules as a side effect of
/// rendering. The view is intentionally empty — the app consumes the ledger
/// write, not the view. Runs only while the host app foregrounds a
/// `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (Int) -> EmptyView = { _ in EmptyView() }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> Int {
        await RuleUsageReportWriter().write(from: data)
        return 0
    }
}
```

- [ ] **Step 4: Extension entry point** — `OpenAppLockReport/OpenAppLockReport.swift`:

```swift
//
//  OpenAppLockReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

@main
struct OpenAppLockReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RuleUsageReport()
    }
}
```

- [ ] **Step 5: Host the report in MainView** — in `OpenAppLock/Views/MainView.swift`, add imports `DeviceActivity`, `FamilyControls`, `ManagedSettings`, then attach a hidden report as a background on `layout`:

```swift
        layout
            .background(ruleUsageReport)
            .task {
                await enforcementLoop()
            }
```
and add:
```swift
    /// An invisible DeviceActivityReport so the report extension recomputes
    /// authoritative usage whenever the app is foreground; the app reads the
    /// resulting ledger writes on its 30 s refresh loop.
    private var ruleUsageReport: some View {
        DeviceActivityReport(.ruleUsage, filter: usageFilter)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var usageFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let interval = DateInterval(start: calendar.startOfDay(for: .now), end: .now)
        var apps: Set<ApplicationToken> = []
        var categories: Set<ActivityCategoryToken> = []
        var webDomains: Set<WebDomainToken> = []
        for rule in rules where rule.kind == .timeLimit && rule.isEnabled {
            let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
            apps.formUnion(selection.applicationTokens)
            categories.formUnion(selection.categoryTokens)
            webDomains.formUnion(selection.webDomainTokens)
        }
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: apps,
            categories: categories,
            webDomains: webDomains)
    }
```

- [ ] **Step 6: Wire files into targets** — in `project.pbxproj`: add the three `OpenAppLockReport/*.swift` files and `Shared/DeviceActivityReportContext.swift` to the **OpenAppLockReport** target's Sources phase; add `Shared/DeviceActivityReportContext.swift` to the **OpenAppLock** app target's Sources phase.

- [ ] **Step 7: Lint + build** — Run `plutil -lint OpenAppLock.xcodeproj/project.pbxproj` (expect `OK`), then Xcode MCP `BuildProject` (simulator). Expected: clean build of the app + all four extensions. Resolve any "missing symbol in OpenAppLockReport" by adding the named Shared file to the report target's Sources phase.

- [ ] **Step 8: Commit**

```bash
git add Shared/DeviceActivityReportContext.swift OpenAppLockReport/ OpenAppLock/Views/MainView.swift OpenAppLock.xcodeproj/project.pbxproj
git commit  # "feat: compute authoritative time-limit usage via DeviceActivityReport" + trailers
```

---

## Task C1: Update docs + memory

**Files:**
- Modify: `Docs/AGENT_RULES_FEATURE_SPEC.md` (§5.5 Reliability posture)
- Modify: `AGENTS.md` (Known gaps / next steps)
- Modify: `~/.claude/projects/-Users-bchendev-Developer-OpenAppLock/memory/openapplock-issue2-usage-counter.md` (+ MEMORY.md pointer if status changes)

- [ ] **Step 1: Update the feature spec §5.5** — describe the collapsed single block event, the confirmed-day-start gate, and the DeviceActivityReport authoritative reconciliation (foreground-only); note the residual background-false-block-until-foreground limit. Read the section first and edit in place to stay accurate.

- [ ] **Step 2: Update AGENTS.md "Known gaps / next steps"** — replace the "stalls at ~14/15m" framing with the new design and the remaining device-verification items (report attribution for categories/web; 4b under-blocking if `intervalDidStart` is skipped; freshness-window tuning). Reference `Docs/Agents/Specs/TIME_LIMIT_COUNTING_HARDENING.md`.

- [ ] **Step 3: Update the issue-2 memory** — note the hardening landed on `feat/time-limit-counting-hardening` (Part A unit-tested; Part B report extension pending on-device verification), so the file reflects current state.

- [ ] **Step 4: Commit** (repo docs only; the memory file lives outside the repo and is saved separately)

```bash
git add Docs/AGENT_RULES_FEATURE_SPEC.md AGENTS.md
git commit  # "docs: record time-limit hardening in the feature spec and known gaps" + trailers
```

---

## Self-Review

- **Spec coverage:** §4a→A2, §4b→A3, §4c→A4, §4d→documented in C1; §5a→B1, §5b→B2+B3, §5c→B4+B5, §5d→B6+B7; §7 test matrix→tasks' TDD steps; §8 sequencing→task order; §9 risks→B6/B7 gates + C1; §10 checklist→C1 / on-device follow-up. `DayStartStore` (§6) → A1.
- **Placeholder scan:** none — every code/test step contains full code; device-only tasks specify exact files, plist/entitlements contents, the pbxproj procedure, and a build gate.
- **Type consistency:** `DayStartStore` API (A1) matches A3/A4 use; `effectiveMinutesUsed(asOf:freshness:)` (B2) matches B4/B5; `recordAuthoritativeMinutes(_:for:onDayContaining:asOf:calendar:)` (B3) matches B7 writer; `blockEvent(forLimit:)` (B1) matches RuleScheduler; `limitReached(given:at:)` (B4) matches all four call sites; `.ruleUsage` context (B7) shared by extension + MainView.
