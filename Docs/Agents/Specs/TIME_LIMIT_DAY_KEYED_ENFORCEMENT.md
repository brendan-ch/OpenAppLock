# Time-Limit Day-Keyed Enforcement

**Status:** Implemented and unit-tested (Tasks 1–6, June 2026); the §14 on-device
checks (monitor self-arm, full-day capture, real-flush drop, activity ceiling)
are pending hardware verification. Closes `TIME_LIMIT_COUNTING_HARDENING.md` §4d's
Scenario B false block at the source.

Design spec for dropping cross-midnight stale time-limit fires **at the source**.
Agent-managed (lives under `Docs/Agents/`). Behavior source of truth is the doc
comments on the owning source files (indexed by the "Rules feature map" in
`AGENTS.md`); this spec is the design rationale.

Extends [`TIME_LIMIT_COUNTING_HARDENING.md`](./TIME_LIMIT_COUNTING_HARDENING.md):
it closes the "Scenario B — false block" residual that spec documented as a
*non-goal* (§4d there), which Part B was meant to merely *correct after the fact*
on foreground.

## 1. Problem

Time-limit rules register threshold events over the rule's selection on
**always-on, `00:00–23:59`, `repeats: true`** activities — the block
(`rule-<uuid>`, one `minutes-<budget>` event) and, when the nudge is on, the warn
(`tlwarn-<uuid>`, one `warn-<budget−lead>` event). Event names are reused every
calendar day and the callback carries `minutes-k` / `warn-k` with **no date**.

`DeviceActivityEvent` thresholds are not a real-time, once-each stream. iOS
coalesces them and flushes when it next wakes the monitor — minutes to hours
late, sometimes triggered by an unrelated wake. A threshold Screen Time held
overnight and flushed after midnight is, by name and count, **byte-identical** to
a fresh one.

### Observed incident (2026-06-29, rule-0F7BDC3D, 30m budget)

- `05:33:13.416Z` `eventDidReachThreshold minutes-30` with `sinceMidnight=93` →
  recorded `0->30`, `limitReached=true` → shield.
- `05:33:13.514Z` the warn event `warn-25` fired in the **same 0.1s**. The warn
  threshold (25m of usage) is five minutes of accrual *before* the block
  threshold (30m); in live accrual they cannot cross in the same instant.
  Co-arrival is the signature of a batched cross-midnight flush — the prior day's
  maxed budget delivered late — not 30 real minutes used before 01:33 local. (The
  warn carries the same staleness class as the block; it merely mis-fires a
  *notification* rather than a block — see §7.)
- The rule then read `used=30/30 blocking=true` across ~20 foreground refreshes
  all day and never cleared.

This is exactly `TIME_LIMIT_COUNTING_HARDENING.md` §1 "Scenario B — false block"
(`usedYesterday ≥ budget ∧ elapsedToday ≥ budget`). It stuck all day because
that spec's Part B foreground reconciliation (`authoritativeMinutesUsed` /
`effectiveMinutesUsed` / `limitReached(at:)`) **was never wired** — `RuleUsageDTO`
carries only `minutesUsed`/`opensUsed`, so nothing re-derives the true total and
overrides the stale record.

### Why no local guard can catch it

The two existing guards in `LimitEnforcement.handleUsageMinutes` both pass for a
post-boundary flush:

- Magnitude (`minutes <= minutesSinceMidnight`, `:100`) only rejects in roughly
  the first `budget` minutes after midnight. At 01:33 (93 min in), `30 ≤ 93`
  passes.
- Confirmed day-start (`hasConfirmedStart(onDayContaining: now)`, `:108`) passes
  because today's `intervalDidStart` already fired (the daily activity is always
  on).

`isScheduledToday` (`:119`) also passes — 2026-06-29 **is** a scheduled day. A
real `minutes-30` and a stale one are indistinguishable by count, timestamp, and
weekday. The missing fact is **which day's interval produced the event**, and the
undated, name-reused event cannot supply it.

## 2. Goals / non-goals

**Goals**

- Make every threshold-carrying time-limit fire — the block **and** the warn —
  **self-dating**, so a cross-midnight stale flush is dropped at the monitor
  entry point, in the background, before it can record a false block (or post a
  spurious "5 minutes left" notification).
- Preserve full-day usage capture and background blocking on genuinely-scheduled
  days.
- Keep all reachable logic unit-testable from the app target; keep the
  device-only surface (the monitor extension) thin.

**Non-goals**

- Changing time-limit user-facing semantics (budget, reset at next local
  midnight, Hard Mode, soft unblock, pause, warn-notification content/timing).
- Reworking open-limit or schedule activities (unchanged — see §7).
- Guaranteeing background coverage when the app is closed across **multiple**
  consecutive days *and* the monitor cannot self-arm (documented limit, §10).
- Finishing Part B. It remains a complementary foreground backstop; this change
  makes it unnecessary for the common case rather than relying on it.

## 3. Approach — per-day, self-dating enforcement activity ("A2")

Replace the always-on, repeating time-limit activities that carry threshold
events — the block (`rule-<uuid>`) and the opt-in warn (`tlwarn-<uuid>`) — with
**per-day, non-repeating** activities:

```
rule-<uuid>-<dayKey>      e.g. rule-0F7BDC3D-…-2026-06-29     (minutes-<budget>)
tlwarn-<uuid>-<dayKey>    e.g. tlwarn-0F7BDC3D-…-2026-06-29   (warn-<budget−lead>)
```

Each:

- spans that day's `[00:00, next-00:00)` local,
- carries its single threshold event over the rule's selection,
- is armed **only for days the rule's weekday set includes** (the warn also
  requires the nudge to be on), so "an activity not scheduled for today" literally
  never exists,
- is **its own clock**: each activity's `intervalDidEnd` (next midnight) arms the
  next scheduled day and stops itself; the **block** activity's `intervalDidStart`
  additionally confirms/zeroes that day's ledger (the warn never touches the
  ledger).

The monitor then drops any block or warn fire whose activity dayKey ≠ today.
Yesterday's flush arrives tagged `…-2026-06-28` and dies at the entry point.
Correctness now rides on the **exact dayKey label**, not on event timing or count.

This is the "Option 2 (per-day event names)" that `TIME_LIMIT_COUNTING_HARDENING.md`
§2 deferred, realized on the **activity name** (which iOS delivers verbatim in the
callback) rather than the event name (fixed by a `repeats: true` registration).
The block and the warn share one per-day plan builder and one re-arm/reaping
lifecycle (§5), differing only in event set, name prefix, and the
`resetsThresholdAccountingOnRestart` flag.

## 4. Naming & parsing (`MonitoringPlan`)

A single day-keyed naming convention serves both prefixes:

- `dailyActivityName(for ruleID: UUID, on day: Date)` →
  `"rule-" + uuid + "-" + UsageLedger.dayKey(for: day)`.
- `warnActivityName(for ruleID: UUID, on day: Date)` →
  `"tlwarn-" + uuid + "-" + UsageLedger.dayKey(for: day)`.
- Both reuse `UsageLedger.dayKey` so the activity dayKey and the ledger key are
  one source.
- `ruleID(fromDailyActivityName:)` / `ruleID(fromWarnActivityName:)` → drop the
  prefix, take the **first 36 chars** (UUID string is fixed-length) as the UUID,
  ignore any remainder. Both recognize the new day-keyed form **and** the legacy
  un-keyed form (`rule-<uuid>` still used by open-limit, §7; either form possibly
  lingering pre-upgrade, §8).
- `dayKey(fromActivityName:) -> String?` → a shared extractor returning the
  trailing `YYYY-MM-DD`, or `nil` for a legacy un-keyed name.

The `sched-`, `sched2-`, `pause-`, `open-session-` prefixes are unaffected.

## 5. Arming lifecycle

Two arming paths, both idempotent (fingerprinted per day-name, so the 30s loop
never thrashes a live activity):

- **Foreground net — `RuleScheduler.sync`.** For each enabled time-limit rule,
  emit per-day plans for the current-or-next scheduled occurrence only (**N = 1**):
  the block plan always, and the warn plan when the nudge is on. One shared
  `dayPlan` builder produces both. As of `RULE_HARD_CAP_AND_N1_ARMING.md`, the
  foreground net **no longer** arms the day after — that day is armed solely by
  the monitor self-arm, a deliberate device trial of that previously-unverified
  path (dropping the old N = 2 buffer also halves the per-rule activity cost so
  the 10-rule cap fits Apple's ~20 ceiling). The declarative reconcile reaps
  past-day activities for free (see below).
- **Background chain — monitor `intervalDidEnd` of a block or warn activity.** Arm
  the next scheduled occurrence of that activity and stop the ended one. This is
  now the **only** path that arms the day after today, and the only path that
  sustains background enforcement with the app closed indefinitely. **It requires
  the monitor extension to call `startMonitoring`, which it currently never does
  (it only ever `stopMonitoring`s)** — a device-verification item (§11), and one
  the N = 1 trial is designed to force observable: with no foreground buffer left,
  a failed self-arm now shows up directly as a lapsed next day (§13). The self-arm
  and the foreground reconcile share no fingerprint state, so each
  must avoid tearing down the other's live activity (a needless restart, EC7):
  the self-arm **skips** a target already in `DeviceActivityCenter().activities`,
  and the foreground reconcile **adopts** a monitored activity that carries no
  recorded fingerprint — records it without a restart — rather than re-arming
  it. (Every `DeviceActivityEvent` this app constructs sets `includesPastActivity:
  true`, so a restart backfills same-interval accrual instead of discarding the
  whole day outright — only up to the current hour is now at risk, per its
  documented hour-rounding — but an avoidable restart is still avoided.)

**Reaping is automatic.** `RuleScheduler.reconcile` already stops any rule-owned
activity not in the freshly-computed desired set (`:214`). Once the §4 parser
recognizes day-keyed block and warn names as rule-owned, past-day activities,
deleted rules, de-scheduled weekdays, and a toggled-off nudge all reap with no new
logic. The monitor's `intervalDidEnd` also stops the just-ended activity (belt and
suspenders).

### Delete / edit (declarative — no special cases)

- **Delete / disable mid-day:** the rule leaves `rules`, so none of its day-keyed
  block/warn names are desired → all stopped by the existing stale pass; the
  shield clear rides the same `RuleEnforcer.refresh → clearShields(except:)` path.
  `stopMonitoring(names:)` already takes an array.
- **Edit budget / selection:** the affected days' block (and warn) plans get a new
  fingerprint → restart. `includesPastActivity: true` (see EC7, §5) backfills
  that day's already-accrued minutes into the new threshold, so a lowered
  budget is enforced against real same-day usage rather than only usage
  accrued after the edit — with the same up-to-an-hour rounding gap as any
  other restart.
- **Edit the `days` set / toggle the nudge:** next `sync` recomputes the next-N
  scheduled occurrences; a removed weekday or a turned-off nudge drops the plan, so
  its activity becomes stale → stopped; an added one is emitted when it enters the
  window. No edit-specific code. Toggling the nudge still never touches the block
  activity (separate plan), so it never resets threshold accounting.

## 6. The drop + the reset

- **Drop (the fix).** Both fire paths extract the activity's dayKey and drop when
  it ≠ `UsageLedger.dayKey(for: now)` before any side effect:
  - block: `LimitEnforcement.handleUsageMinutes(_:ruleID:activityDayKey:…)` drops
    before the ledger write, logging
    `drop rule-… : stale day-keyed flush (activity=<dayKey> today=<dayKey>)`.
  - warn: the warn branch drops before `LimitWarningNotifier.notifyIfEligible`.
  Putting the comparison in the shared/handler logic (not the extension shell)
  keeps it unit-testable from the app target. A budget-reached fire for day D
  coalesced past midnight is processed with `now` in D+1 and therefore dropped —
  at most the final sliver of D's usage is lost, which the next-midnight reset
  would clear anyway.
- **Reset.** `confirmDayStart` + zero-the-ledger moves to the **block** activity's
  `intervalDidStart`, confirming the day from `now`. (A very late `intervalDidStart`
  would confirm against `now`'s day rather than the activity's day key; the
  same-day re-fire guard in `confirmDayStart` keeps that from re-zeroing a day
  that already started. Threading the name's day key through is a future
  hardening.) The warn activity's edges never touch the ledger.
- **Existing guards stay as defense-in-depth.** The magnitude and confirmed-start
  guards and the eligibility guard remain — cheap, and they still cover the
  upgrade window (a legacy un-keyed event) and the safety-net mid-day arming case.
  The dayKey drop is the new *primary, exact* guard.

## 7. Out of scope (unchanged), with rationale

The split is principled: **activities that carry usage/threshold events are
day-keyed (block, warn); event-less gate/clock activities stay repeating.**

- **Open-limit rules** keep the legacy repeating `rule-<uuid>` activity. They
  carry no usage events (no stale-flush class) and rely on a repeating
  `intervalDidStart` for the proactive gate — which is observed reliable and would
  *regress* if made dependent on a daily re-arm. The §4 parser recognizes both
  forms, so reconcile and uninstall-protection keep working.
- **Schedule windows, pause re-arm, open sessions** — untouched (event-less clocks
  / one-shots).

The warn was previously scoped out; it is now folded in because it shares the
exact staleness class and, with the per-day primitive built for the block, sharing
one builder + one re-arm/reaping lifecycle is *less* code than maintaining the
warn as a repeating exception (and it fixes the warn's spurious-notification
variant of the bug for free).

## 8. Migration

No data migration. The ledger and `DayStartStore` are already keyed by calendar
day. On upgrade, a time-limit rule's legacy `rule-<uuid>` / `tlwarn-<uuid>`
activities are simply not in the new desired set, so the first `sync` reaps them
and arms the day-keyed activities. The §4 parser ensures the legacy names are
recognized as rule-owned so they are reaped rather than orphaned.

## 9. Full-day capture & the mid-day arming caveat

A `DeviceActivityEvent` threshold counts usage **from when monitoring began**, not
from the schedule's nominal `intervalStart`. So a per-day activity must be armed
*at or before* its day's `00:00` to capture the whole day.

- **Primary path** (monitor `intervalDidEnd` at the prior midnight) registers the
  next day's activity before its midnight → full capture. With N = 1, this is now
  the *only* path that arms a day before it starts — the foreground net no longer
  arms ahead (see §5, §13).
- **Safety-net mid-day arming** (monitor self-arm failed *and* the app is first
  opened mid-day) counts only from the arming instant → undercounts that morning.
  This is the same class as today's mid-day rule creation, is bounded, and is
  re-derived by the foreground report if/when Part B is finished. Under N = 1 this
  case is reached whenever the self-arm fails, not only on the very first day —
  the trial this change is running. (The warn is unaffected in practice — a
  late-armed warn just fires its notification slightly late or not at all, never
  mis-blocks.)

## 10. Activity-count budget

Per time-limit rule (N = 1, see `RULE_HARD_CAP_AND_N1_ARMING.md`): 1 day-keyed
block activity (today) and, when the nudge is on, 1 day-keyed warn activity —
**≈ 2** per nudge-enabled rule, down from the prior N = 2 design's ≈ 4. Without
the nudge it is 1. Against DeviceActivity's documented ceiling (~20 concurrent
activities — confirm on device) that is ~10 nudge-enabled time-limit rules before
crowding — which is exactly why `RuleCreationPolicy` caps total rules at 10.

## 11. Testing strategy (red/green TDD)

Unit-tested from the app target (mock monitor, `freshDefaults()`, `date()`, `utc`,
mirroring `SchedulingTests` / `LimitEnforcementTests`):

- **MonitoringPlan** — `dailyActivityName(for:on:)` / `warnActivityName(for:on:)`
  round-trip; `ruleID(from…)` recovers the UUID from **both** the day-keyed and
  legacy forms for each prefix; `dayKey(fromActivityName:)` returns the trailing
  date / nil.
- **RuleScheduler** — `sync` emits per-day block (and, when the nudge is on, warn)
  plans for the next N scheduled occurrences, skips non-scheduled weekdays, keeps a
  stable fingerprint across a same-day re-sync, and (via reconcile) stops past-day,
  deleted-rule, de-scheduled-day, and nudge-toggled-off activities. Delete/disable
  stops all of a rule's day-keyed names; an edit restarts the affected days;
  toggling the nudge never restarts the block.
- **LimitEnforcement** — `handleUsageMinutes` drops a block event whose
  `activityDayKey` ≠ today and records one whose dayKey == today; the warn path
  drops a stale-dayKey warn before notifying; `confirmDayStart`/zero fires on the
  block's per-day `intervalDidStart` and is a no-op on a same-day re-fire.

Device-only (written + build-verified, deferred; the simulator delivers no
DeviceActivity callbacks):

- The monitor extension can **start** monitoring from `intervalDidEnd` (next-day
  self-arm) for both block and warn activities.
- Full-day capture from a midnight-armed per-day block activity.
- A real cross-midnight flush (block and warn) arrives tagged with the prior dayKey
  and is dropped.
- Activity-count ceiling with several concurrent nudge-enabled time-limit rules.

## 12. Sequencing

1. `MonitoringPlan` naming + parser (day-keyed + legacy, both prefixes) — TDD.
2. `RuleScheduler` shared `dayPlan` builder + per-day block/warn emission (next N
   scheduled) + reaping — TDD.
3. `LimitEnforcement` dayKey drop (block + warn) + `confirmDayStart`/zero
   migration — TDD.
4. Monitor `intervalDidEnd` self-arm (block + warn) + threading the activity dayKey
   into the block and warn handlers — build-verified.
5. Update owning-source doc comments, `AGENTS.md` ("Rules feature map" + "Known
   gaps"), and this spec's status; note the relationship to
   `TIME_LIMIT_COUNTING_HARDENING.md` §4d.

Build and test via the Xcode MCP on the simulator (no raw `xcodebuild`).

## 13. Risks

- **Monitor-initiated `startMonitoring` is unverified.** As of
  `RULE_HARD_CAP_AND_N1_ARMING.md`, the old foreground N = 2 mitigation is
  deliberately removed: N = 1 makes the self-arm's real-device reliability
  load-bearing and observable, rather than papered over by a foreground buffer.
  If the self-arm does not fire, the next scheduled day simply goes unarmed until
  the app is next opened (§14).
- **Activity ceiling** (§10) — verify on device; N = 1 is itself the mitigation
  the old spec proposed here, now adopted (see `RULE_HARD_CAP_AND_N1_ARMING.md`).
- **Mid-day arming undercount** (§9) — bounded; corrected by the report. More
  frequent under N = 1 since it is reached by any single failed self-arm, not
  only exhaustion of a multi-day buffer.
- **Timezone / clock change.** The drop compares the activity's baked-in day key
  against a *live* `UsageLedger.dayKey(for: now)`. If the device timezone or clock
  moves the local calendar date away from the active activity's armed day (e.g.
  westward travel rolling the date back, or the clock set forward past midnight),
  a genuine same-day budget-reached fire can satisfy `activityDayKey != today` and
  be dropped → the limit is not enforced for that occurrence. The old always-on
  `00:00–23:59 repeats:true` activity re-anchored to local midnight each day and
  had no baked date to disagree with, so this specific false-drop is new (clock-
  forward already grants a fresh budget under any design — a pre-existing Screen
  Time weakness). Accepted for now; a future hardening would derive "today" from
  the firing schedule's own interval rather than live `now`.
- **Multi-day app-closed weakens Hard Mode / Uninstall Protection, now starting
  after a single closed day.** Under N = 1 the foreground-armed window is just
  today; background coverage lapses as soon as the monitor fails to self-arm the
  next day, and the app re-arms on next open. This trades the old N = 2 design's
  one-day grace period (and the prior always-on activity's indefinite coverage)
  for the staleness fix and the device trial, consistent with "the app is the
  source of truth whenever it runs." For a **Hard Mode** time-limit rule the same
  lapse reduces the "can't be bypassed" guarantee in the background to a single
  closed day (down from ≈2), and Uninstall Protection — which keys off ledger
  usage — lifts with it. Restoring longer unattended coverage depends on the
  monitor self-arm being verified on device (see `RULE_HARD_CAP_AND_N1_ARMING.md`).

## 14. On-device verification checklist (deferred)

**N = 1 (`RULE_HARD_CAP_AND_N1_ARMING.md`) makes the monitor self-arm
load-bearing:** with no foreground buffer, the items below now depend on
`DeviceActivityMonitorExtension.reArmNextScheduledDay` actually calling
`startMonitoring` at `intervalDidEnd` — the very capability this trial exists to
observe.

- A maxed-out day does **not** re-block unused apps the next morning (the
  2026-06-29 incident) — the next day's fire is dropped as a stale-dayKey flush.
- The next morning shows **no** spurious "5 minutes left" warn notification from a
  cross-midnight warn flush.
- A genuinely-scheduled day still blocks at the budget, with full-day capture (no
  morning undercount when armed at midnight), and the warn still fires ~5 min out.
  Under N = 1 this specifically verifies the self-arm fired before that midnight —
  see `RULE_HARD_CAP_AND_N1_ARMING.md`.
- Deleting / disabling / editing a time-limit rule, and toggling the nudge, stop or
  restart the correct day-keyed activities with no orphans (inspect
  `center.activities`); toggling the nudge never resets the block's count.
- Open-limit proactive gating is unchanged.
