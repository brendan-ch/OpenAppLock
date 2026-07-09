# Rule hard cap (10) + N=1 time-limit arming

**Status:** Design approved 2026-07-08; not yet implemented. Rebased onto
`origin/main` @ `175cf00` (v1.0.2 — app-icon + version-bump merges only; that
merge touched just the app icon and `project.pbxproj`, so every code/test line
reference below is unchanged).

Two coupled changes:

1. **N=1 arming** — drop `RuleScheduler.dayActivityHorizon` from 2 to 1 so a
   time-limit rule arms only *today's* per-day activities, leaning entirely on the
   monitor's midnight self-arm for the next day. This is a deliberate **device
   trial** (TestFlight): the self-arm (`DeviceActivityMonitorExtension.reArmNextScheduledDay`)
   is written and unit-tested but never verified on a real device
   (`TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` §14). N=1 removes the foreground safety
   net so the self-arm's real-device behavior becomes observable.
2. **10-rule hard cap** — refuse to create an 11th rule and show an alert.

## Motivation

Apple caps a `DeviceActivityCenter` at ~20 concurrent activities. Per-rule cost
today (see `TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` §10):

| Rule kind | N=2 (today) | N=1 (this change) |
|---|---|---|
| Open-limit | 1 | 1 |
| Schedule, no midnight cross | 1 | 1 |
| Schedule, crosses midnight | 2 | 2 |
| Time-limit, nudge off | 2 | **1** |
| Time-limit, nudge on | 4 | **2** |

Worst case per rule falls from 4 to **2** (nudge-on time-limit). A flat cap of
**10 rules** then keeps the worst case at 10 × 2 = **20 activities**, exactly the
ceiling — while covering every cheaper mix with headroom. Transient one-shots
(`pause-`, `open-session-`) can still momentarily exceed the ceiling; that is
accepted (they are best-effort, with the foreground reconcile as the net) and out
of scope here.

## Part A — N=1 arming

### Change

- `RuleScheduler.dayActivityHorizon`: `2 → 1` (`OpenAppLock/Services/RuleScheduler.swift:53`).
  Nothing else in `dayPlans` changes — it already loops
  `ScheduledDayPlanner.upcomingScheduledDayStarts(count: dayActivityHorizon)`, which
  returns just the current-or-next scheduled day when `count == 1`.

### Behavior after the change

- A time-limit rule arms **only today's** block activity (`rule-<uuid>-<todayKey>`),
  plus today's warn activity (`tlwarn-<uuid>-<todayKey>`) when the nudge is on.
- The **next scheduled day is armed solely by the monitor self-arm** at the prior
  midnight (`reArmNextScheduledDay`). If that callback does not fire on device, the
  rule stops enforcing until the app is next opened and `sync` re-arms today. This
  loss of the foreground buffer is the whole point of the trial — we want to learn
  whether the self-arm is reliable enough to stand alone.
- Schedule and open-limit arming are unchanged.

### Doc + spec updates (same change)

- `dayActivityHorizon` doc comment (`RuleScheduler.swift:50-53`) and the `dayPlans`
  doc comment (`:179-184`): describe N=1 (today only) and the device-trial rationale.
- `TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md`: §5 (N=2 → N=1, foreground net removed for
  the trial), §10 (budget table now ~2 per nudge-on rule), and the §13/§14 notes on
  the self-arm now being the sole next-day path.
- `AGENTS.md` "Known gaps" time-limit day-keyed bullet: note N=1 + the cap.

### Tests to update (they encode N=2 today)

All are the expected TDD "red → green" flips to N=1 expectations:

- `SchedulingTests.timeLimitArmsTwoDayKeyedActivities` (`:188`) — rename/retarget to
  "arms today only": assert today armed **and tomorrow NOT armed**.
- `SchedulingTests.dayRolloverReapsPastActivity` (`:210`) — sync 01-06 arms only 06;
  sync 01-07 arms 07 and reaps 06; assert 08 is **not** armed.
- `SchedulingTests.adoptsSelfArmedActivity` (`:226`) — after adopting today's
  self-armed activity, **no** new start (`startCallCount == startsAfterSelfArm`),
  since there is no tomorrow to arm.
- `SchedulingTests.avoidsRestartChurn` (`:424`) — `startCallCount == 1` (today only),
  and `== 2` after a budget change (the one day activity restarts).
- `RuleSchedulerWarnTests.togglingNudgeLeavesBlockActivityUntouched` (`:92`) — nudge
  off → `startCallCount == 1`; nudge on → `2`; comments updated ("today only").

Unaffected: `RuleSchedulerPlanTests` (`:138` is the midnight-crossing *schedule*
count, independent of the horizon) and `ScheduledDayPlannerTests` (pass explicit
`count` values).

## Part B — 10-rule hard cap + alert

### `RuleCreationPolicy` (new, pure)

`OpenAppLock/Logic/RuleCreationPolicy.swift` — matches the pure, unit-tested
`Logic/` pattern:

```swift
enum RuleCreationPolicy {
    /// Hard cap on total rules. Chosen so the worst-case DeviceActivity cost
    /// (N=1 nudge-on time-limit = 2 activities/rule) stays within Apple's ~20
    /// ceiling: 10 × 2 = 20. Counts ALL rules, enabled or not.
    static let maxRuleCount = 10

    static func canCreateRule(existingRuleCount: Int) -> Bool {
        existingRuleCount < maxRuleCount
    }
}
```

Counts **all** rules (enabled or not) — a safe over-approximation; no separate cap
on *enabling* a rule is needed.

### `RulesListView`

- `@State private var showingRuleLimitAlert = false`.
- One `attemptNewRule()` routes both the toolbar `newRuleButton` (`:28`) and the
  empty-state button (`:55`): `canCreateRule(existingRuleCount: rules.count)` →
  `showingNewRule = true`, else `showingRuleLimitAlert = true`. (The empty-state
  button is only visible at 0 rules, so it never trips the cap; routing both keeps
  one code path.)
- `.alert` following the `AppListLibraryView` pattern (`:125`):

```swift
.alert(Text(.rulesListRuleLimitAlertTitle), isPresented: $showingRuleLimitAlert) {
    Button(CopyKey.appListsOkButtonLabel.resource, role: .cancel) {}
} message: {
    Text(CopyKey.rulesListRuleLimitAlertMessage.string(RuleCreationPolicy.maxRuleCount))
}
```

### Copy (new `CopyKey` cases + `Copy.xcstrings` entries)

`CopyCatalogTests` requires every key to have a catalog entry.

| Key | Raw value | String |
|---|---|---|
| `rulesListRuleLimitAlertTitle` | `rulesList.ruleLimitAlertTitle` | `Rule limit reached` |
| `rulesListRuleLimitAlertMessage` | `rulesList.ruleLimitAlertMessage` | `You can have up to %lld rules. Delete one to add another.` |

OK button reuses the existing `appListsOkButtonLabel` ("OK"). The message is a
`%lld` format fed `RuleCreationPolicy.maxRuleCount`, so "10" has a single source of
truth.

## Part C — Tests

### Unit

- `RuleCreationPolicyTests` — boundaries: `canCreateRule(existingRuleCount:)` is
  `true` for 0 and 9, `false` for 10 and 11.
- The N=1 scheduler-count updates from Part A.

### UI — seed scenario + `RuleLimitUITests`

- New scenario `LaunchConfiguration.SeedScenario.atRuleCap = "at-rule-cap"`;
  `SampleRules.seed` inserts **exactly 10** rules (distinct names, e.g. schedule
  rules "Rule 01"…"Rule 10", all `Weekday.everyDay`, wired to the shared app list).
- `OpenAppLockUITests/RuleLimitUITests.swift`:
  - **Alert shows (the requested test):** launch
    `-ui-testing -onboarding-completed -seed-scenario=at-rule-cap` → Rules tab → tap
    `newRuleButton` → assert `app.alerts["Rule limit reached"]` appears **and** the
    editor (`ruleEditorTitle`) does not. (UI tests query alerts by literal string,
    per `AppListUITests.swift:270`.)
  - **Alert absent (guards "only shows"):** launch `-seed-scenario=standard`
    (2 rules) → tap `newRuleButton` → editor opens, no alert.
  - Both run on the iPhone + iPad matrix via the idiom-aware nav helpers
    (`goToRulesTab()` / `waitForMainUI()`).

## Sequencing (TDD)

1. `RuleCreationPolicy` + `RuleCreationPolicyTests` (red → green).
2. N=1: update the affected scheduler tests to N=1 expectations (red), flip
   `dayActivityHorizon` to 1 (green), update doc comments + spec + AGENTS.md.
3. `RulesListView` cap wiring + copy (`CopyKey` + `Copy.xcstrings`); `CopyCatalogTests`
   stays green.
4. `atRuleCap` seed scenario + `RuleLimitUITests` (both branches).
5. Full suite; manual UI validation on simulator (or hand back if MCP/simulator
   unavailable this session).

## Out of scope (YAGNI)

- No cap on *enabling* rules (we count total).
- No change to schedule/open-limit arming.
- No "10/10 used" counter UI — only the alert.
- Transient `pause-`/`open-session-` activities are not counted against the cap.
