# Time-Limit Counting Hardening

Design spec for making time-limit enforcement robust against unreliable Screen
Time threshold events. Agent-managed (lives under `Docs/Agents/`). Pairs with
`Docs/AGENT_RULES_FEATURE_SPEC.md` (the behavior source of truth) and updates
its §5.5 "Reliability posture" once shipped.

## 1. Problem

Time-limit rules count usage by registering a chain of cumulative
`DeviceActivityEvent` thresholds (`minutes-1 … minutes-N`) over the rule's app
selection on an always-on, midnight-to-midnight repeating activity
(`MonitoringPlan.minuteEvents(forLimit:)`, `RuleScheduler.sync`). When a
threshold is crossed the monitor extension records the minute count and shields
at the budget (`LimitEnforcement.handleUsageMinutes`).

`DeviceActivityEvent` thresholds are **not** a real-time, ordered, once-each
stream. iOS coalesces closely-spaced thresholds and flushes them when it next
wakes the monitor — often minutes to hours late, sometimes triggered by an
unrelated wake. Because the daily activity is `repeats: true`, every day reuses
the same event names, and a callback carries `minutes-k` but **no date**. So an
event Screen Time held overnight and flushed after midnight is
indistinguishable, by name, from a fresh one. (Corroborated by Apple Developer
Forums threads on `eventDidReachThreshold` batching/overcounting, and by this
project's device-research notes: the Usage counter "stalls at ~14/15m".)

The existing mitigation is a magnitude guard
(`LimitEnforcement.handleUsageMinutes`):

```swift
let minutesSinceMidnight = Int(now.timeIntervalSince(calendar.startOfDay(for: now)) / 60)
guard minutes <= minutesSinceMidnight else { return }
```

It rejects a stale checkpoint only when its threshold exceeds today's elapsed
minutes — i.e. only in roughly the first `budget` minutes after midnight. Two
failure modes survive it:

- **Scenario A — under-count.** Yesterday's modest usage (say 20m) flushes
  mid-morning (elapsed = 480m). Every `minutes-1 … minutes-20` event passes the
  guard and corrupts today's ledger with phantom usage, silently shrinking
  today's real budget.
- **Scenario B — false block.** Yesterday maxed the budget; the `minutes-<budget>`
  event flushes the next morning after `intervalDidStart` already cleared the
  shield. `budget ≤ elapsed` passes the guard, the ledger records the full
  budget, and apps the user never opened today are re-blocked all day. General
  condition: `usedYesterday ≥ budget ∧ elapsedToday ≥ budget`.

Aggravating: `recordMinutesUsed` runs **before** the
`isEnabled / kind / !isPaused / isScheduledToday` eligibility guards, so a stale
event corrupts today's ledger even for a rule that cannot be active today, and
the foreground `RuleEnforcer.refresh` later reads that corrupted value.

## 2. Goals / non-goals

**Goals**

- Eliminate, or correct within one foreground refresh, the phantom blocks and
  under-counts caused by cross-midnight stale threshold flushes.
- Provide an authoritative daily usage total for display and for the foreground
  block decision, fixing the "stalls at ~14/15m" lag.
- Keep all reachable logic unit-testable from the app target; keep the
  device-only surface (a new extension) as thin as possible.

**Non-goals**

- Fully eliminating background false blocks while the app is never opened. That
  needs per-day event names (the previously-discussed "Option 2"), which we are
  not doing here. With this design a residual background false block is
  *corrected on the next foreground refresh*, not prevented in pure background.
- Changing time-limit user-facing semantics (budget, reset at next midnight,
  Hard Mode, soft unblock).

## 3. Architecture

Two complementary parts:

- **Part A (Option 3) — background hardening.** Shrinks the surface that can
  corrupt the threshold-derived ledger at the source. Fully unit-tested. Ships
  first and stands alone.
- **Part B (Option 1) — foreground authoritative reconciliation.** A
  `DeviceActivityReport` extension computes the true daily total while the app
  is foreground and writes it to the app group; the app prefers that
  authoritative total for display and for the foreground block decision,
  overriding any residual threshold corruption.

`DeviceActivityReport` is a SwiftUI view whose data is computed in a separate
extension process **only while the view is rendered in the foreground app**. It
cannot feed the background monitor's block decision. Therefore Part A governs
the background; Part B governs the foreground and reconciles. A false block is
prevented in the common case (A) or cleared the moment the app is opened (B).

## 4. Part A — background hardening

### 4a. Record only for eligible rules

In `LimitEnforcement.handleUsageMinutes`, move `ledger.recordMinutesUsed(...)`
**below** the eligibility guards (`isEnabled`, `kind == .timeLimit`,
`!isPaused`, `isScheduledToday`). A rule that cannot be active today no longer
accrues phantom usage today. (The daily activity runs every day regardless of
the rule's selected days, so today's events still arrive on an unscheduled day;
we simply stop recording them.)

### 4b. Confirmed day-start gate

Add `DayStartStore` in the app group: `ruleID → confirmed day-start Date`
(stored in `AppGroup.defaults`, same pattern as `RuleSnapshotStore`).

- `handleDayStart` (fired by `intervalDidStart` for the daily activity): on a
  genuine new-day transition only — `confirmedStart(ruleID) != startOfDay(now)`
  — record `startOfDay(now)` as the confirmed start **and zero today's ledger
  once**. Zeroing only on the transition is safe against a spurious mid-day
  `intervalDidStart` re-fire (which would otherwise erase legitimate usage).
- `handleUsageMinutes`: after the magnitude guard, drop the event unless
  `confirmedStart(ruleID) == startOfDay(now)`. This closes the *pre-boundary*
  race — a stale flush that lands in the early morning before today's
  `intervalDidStart` fires, in the window where the magnitude guard alone would
  let it through (e.g. `intervalDidStart` delayed to 00:50, a `minutes-45`
  residual arrives at 00:46: magnitude `45 ≤ 46` passes, but no confirmed start
  for today exists yet → dropped).

### 4c. Foreground safety net

`RuleEnforcer.refresh` (foreground, runs on launch / rule change / every 30s)
**establishes a confirmed start for today if one is missing**, without zeroing
(to preserve any legitimate accrual). This bounds 4b's failure mode: if the
monitor's `intervalDidStart` is skipped for a day, the gate would otherwise
block all usage recording for that day; the safety net self-heals it the next
time the app is foregrounded.

### 4d. Limits of Part A (documented, not fixed here)

4b adds day-attribution only for the *pre-boundary* race. The *post-boundary*
Scenario B (interval fires, then a stale `minutes-<budget>` flush arrives) still
passes the magnitude guard and the confirmed-start gate, so a background false
block can still occur — it is cleared by Part B on the next foreground refresh.
4b also trades a small under-blocking risk (skipped `intervalDidStart` → no
recording until the app is next opened) for the under-count/false-block fix;
acceptable because the app is the source of truth whenever it runs, and Part B
re-derives the true total on foreground. Both are device-verification items.

## 5. Part B — foreground authoritative reconciliation

### 5a. Collapse the event chain

`MonitoringPlan` returns a **single** `minutes-<budget>` block event for a time
limit instead of `minutes-1 … minutes-N`. Rename `minuteEvents(forLimit:)` →
`blockEvent(forLimit:)` (one-entry dictionary), keeping `minuteEventName` /
`minutes(fromEventName:)` for the name round-trip. `RuleScheduler.sync` calls
the new function. Background still blocks at the budget via that one event; the
cross-midnight stale surface shrinks to its minimum (only one event can ever
mis-fire). Live sub-budget progress now comes from the report (5c), not from the
per-minute chain — acceptable because the limited apps only accrue time while
OpenAppLock is *not* foreground, so "live" already meant "accurate as of when
you open the app."

### 5b. Authoritative usage in the ledger

Extend `RuleUsage` (tolerant `Codable`, optional fields so old blobs decode):

```swift
var authoritativeMinutesUsed: Int?     // true daily total from the report
var authoritativeAsOf: Date?           // when the report computed it

static let authoritativeFreshness: TimeInterval = 120  // tunable on device

func effectiveMinutesUsed(asOf now: Date,
                          freshness: TimeInterval = RuleUsage.authoritativeFreshness) -> Int {
    if let a = authoritativeMinutesUsed, let at = authoritativeAsOf,
       abs(now.timeIntervalSince(at)) <= freshness { return a }
    return minutesUsed
}
```

Add `UsageLedger.recordAuthoritativeMinutes(_:for:onDayContaining:asOf:)` (sets
the authoritative fields without disturbing the monotonic `minutesUsed`).

One resolver serves both contexts correctly:

- **Foreground:** the report keeps `authoritativeAsOf` fresh → authoritative
  wins → fixes display lag and overrides residual threshold corruption.
- **Background:** authoritative is stale → falls back to `minutesUsed` (the
  collapsed block event) → unchanged background behavior.

### 5c. Consume effective minutes

`limitReached` gains a `now` parameter and uses `effectiveMinutesUsed(asOf: now)`
in the time-limit branch (both `BlockingRule.limitReached` and
`RuleSnapshot.limitReached`; schedule/open-limit branches unchanged). The four
direct call sites already have `now` in scope: `BlockingRule.status`
(`RuleStatus.swift`), the three `LimitEnforcement` handlers, and
`UninstallProtectionPolicy.isActive`. `RulePolicy.shouldDenyAppRemoval` needs no
change — it routes through `rule.status(at:…)`, which already passes `now`.
`UsageDisplay.usagePhrase` gains a `now` parameter to compute effective minutes,
supplied by its only caller `BlockingRule.rowContext` (which already takes
`relativeTo now`). No new branch is needed in `RuleEnforcer`: once status uses
effective minutes, a fresh authoritative total below budget makes a rule's
status non-active, so the existing `clearShields(except:)` clears the phantom
shield automatically.

### 5d. Report extension (`OpenAppLockReport`, device-only)

New app-extension target added by mirroring the three existing extensions in
`project.pbxproj` (same app group + Family Controls entitlement; bundle id
`dev.bchen.OpenAppLock.Report`). Contents:

- A `DeviceActivityReport.Context` value `.ruleUsage` and a
  `DeviceActivityReportScene` whose `makeConfiguration(representing:)` reads the
  rule snapshots, and for each enabled time-limit rule sums
  `totalActivityDuration` over that rule's selection for the current day, then
  calls `recordAuthoritativeMinutes`. The rendered view is empty/zero-size — we
  use the scene only for its side effect.
- Attribution: the host filter covers the union of all time-limit rules'
  selections over a `.daily` segment; the scene iterates segments → categories →
  applications and, per rule, sums durations whose app/category token is in that
  rule's selection. Overlapping rules each sum their own selection (independent
  budgets).

Host wiring: `MainView` embeds an invisible
`DeviceActivityReport(.ruleUsage, filter:)` so it renders whenever the app is
foreground; the filter is rebuilt from the current rules. The existing 30s
`RuleEnforcer.refresh` loop picks up the freshly-written authoritative totals
(snappier app-group key observation is possible later but not required for
correctness).

## 6. Data model / API changes

- `RuleUsage`: `+ authoritativeMinutesUsed: Int?`, `+ authoritativeAsOf: Date?`,
  `+ effectiveMinutesUsed(asOf:freshness:)`, `+ static authoritativeFreshness`.
- `UsageLedger`: `+ recordAuthoritativeMinutes(_:for:onDayContaining:asOf:)`;
  add `MockUsageLedger` seeding for the new fields.
- `MonitoringPlan`: `minuteEvents(forLimit:)` → `blockEvent(forLimit:)`.
- `LimitEnforcement`: reordered `handleUsageMinutes`; confirmed-start gate;
  `handleDayStart` records confirmed start + zeroes once; new `DayStartStore`
  dependency (injectable, app-group-backed, with a mock/fresh-defaults variant
  for tests).
- `DayStartStore`: new file in `Shared/`.
- `limitReached(given:at:)` on `BlockingRule` and `RuleSnapshot`; the four
  direct call sites updated (`RulePolicy` unchanged — routes via `status`).
- `UsageDisplay.usagePhrase(...,asOf:)` + `BlockingRule.rowContext` passes `now`.
- `RuleEnforcer.refresh`: confirmed-start safety net.
- New target `OpenAppLockReport` + host `DeviceActivityReport` view in `MainView`.

## 7. Testing strategy (red/green TDD)

Each change starts with a failing test (Swift Testing, mirroring
`SchedulingTests` patterns: `freshDefaults()`, `MockShieldController`, `date()`,
`utc`).

Unit-tested (must be red first, then green):

- **4a** — a disabled / paused / not-scheduled-today rule does not accrue
  minutes from an in-range event (`LimitEnforcementTests`).
- **4b** — an in-range event before a confirmed day-start is dropped; after a
  confirmed start it records; `handleDayStart` zeroes only on the day transition
  and not on a same-day re-fire (`LimitEnforcementTests`, `DayStartStore` test).
- **4c** — `RuleEnforcer.refresh` establishes a confirmed start for today when
  missing, without zeroing existing usage (`RuleEnforcerTests`).
- **5a** — `blockEvent(forLimit:)` returns one entry; `RuleScheduler` registers
  one event; update the two affected `SchedulingTests`.
- **5b** — `effectiveMinutesUsed` prefers fresh authoritative, falls back when
  stale; `RuleUsage` Codable round-trips the new fields and decodes legacy
  blobs; `recordAuthoritativeMinutes` round-trips (`UsageTests`).
- **5c** — `limitReached(at:)` uses fresh authoritative; a fresh authoritative
  below budget makes status non-active and clears the shield via
  `RuleEnforcer.refresh` (`RuleStatusTests`, `RuleEnforcerTests`); `UsageDisplay`
  shows the effective figure.

Device-only (written + build-verified, **not** unit-tested; deferred
verification): the `OpenAppLockReport` scene + token-matching aggregation, the
invisible host report view, and the `project.pbxproj` target. The simulator
delivers no DeviceActivity data and does not render custom report extensions.

## 8. Sequencing

1. Part A (4a, 4b, 4c) — self-contained, shippable.
2. Part B shared logic (5a, 5b, 5c) — TDD.
3. Part B extension + pbxproj + host view (5d) — build-verified.
4. Update `Docs/AGENT_RULES_FEATURE_SPEC.md` §5.5 and AGENTS.md "Known gaps",
   and the `openapplock-issue2-usage-counter` memory.

Build and test via the Xcode MCP on the simulator (no raw `xcodebuild`).

## 9. Risks

- **pbxproj hand-edit** can corrupt the project; verify the project opens and
  builds after the edit, before writing extension code.
- **Freshness window** (120s) is a guess; tune on device so foreground stays
  fresh across the 30s refresh cadence without trusting a stale reading.
- **4b under-blocking** if `intervalDidStart` is skipped all day and the app is
  never opened (bounded by 4c + Part B). Device-verification item.
- **Report attribution** for category/web selections is unverified on device;
  start with application tokens and confirm category coverage on hardware.

## 10. On-device verification checklist (deferred)

- Time-limit usage accrues in the Usage section and reads the true total on app
  open (no "stalls at 14/15m").
- Blocks at the budget; a maxed-out day does **not** re-block unused apps the
  next morning (or clears within one foreground refresh if it does).
- A modest prior day does not shrink today's budget (no Scenario A under-count).
- Collapsed single event still blocks in pure background.
