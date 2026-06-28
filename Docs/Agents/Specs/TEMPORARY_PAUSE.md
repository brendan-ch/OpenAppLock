# Temporary Pause

Status: **Designed** (2026-06-28) — not yet implemented · Branch:
`feat/temporary-pauses`

Design spec for replacing the current "Unblock" affordance with a **Temporary
Pause** that lifts an individual block for 15 minutes and re-engages it
automatically. Agent-managed (lives under `Docs/Agents/`). The behavior source
of truth, once implemented, is the doc comments on the owning source files
(indexed by the "Rules feature map" in `AGENTS.md`); this spec is the design
rationale behind those changes.

## 1. Motivation

Today a blocking soft rule can be "unblocked" from Home's **Currently Blocking**
section: a tap opens an "Unblock <name>?" dialog, and confirming pauses the rule
for the **rest of its window/day** (`RulePolicy.unblock` sets
`pausedUntil = window.end` for schedule rules, `nextMidnight` for limit rules).
This is confusing: "Unblock" reads as "turn the block off," the relief silently
lasts hours, and the control lives on Home rather than where the user inspects a
rule.

Replace it with a **Temporary Pause**: an explicit, time-boxed 15-minute lift
that re-activates on its own, surfaced on the rule-viewing overlay where the user
already goes to act on a rule.

## 2. Behavior

### Per rule kind

| Kind | Pause available? | Effect of pausing |
|---|---|---|
| **Schedule** | When actively blocking (window open) | Removes the block for 15 min, then the window's shield returns |
| **Time Limit** | When actively blocking (budget spent) | Lifts the block for 15 min, then re-blocks (budget is still spent) |
| **Open Limit** | **Never** | — |

### Availability gate

The Pause control appears only when **all** hold:

- the rule is **actively blocking** right now (`activation().isBlocking`);
- the kind is **Schedule or Time Limit** (Open Limit is excluded);
- **Hard Mode is off** (a hard block can never be weakened while active);
- the block has **more than 15 minutes remaining** (`blockEnd − now > 15 min`).

The last clause is what avoids the "pause outlives the block" edge entirely: when
Pause is offered, the block always outlasts the pause, so `pausedUntil` is always
strictly before the block's natural end, the background re-arm is always a valid
(≥15-min) activity, and the paused countdown always names a real resume moment.
When a block has ≤15 min left, no Pause is offered — the block is nearly over
anyway.

`blockEnd` is the `until:` date from `.active(until:)`: the window end for a
schedule rule, the next midnight for a time-limit rule (the same values
`RulePolicy` computes today).

### Paused state

While paused:

- The rule reports `.paused(until:)` (it is not "blocking", so it leaves
  **Currently Blocking** and appears under **Active Rules**).
- Its status label is a **live countdown**: "Resumes in 12m".
- The overlay shows **Resume Blocking** instead of Pause.

After 15 minutes the rule re-activates automatically (see §4). **Resume Blocking**
re-activates it instantly.

### Hard Mode

Unchanged in spirit: a hard-mode rule that is actively blocking already shows the
"Hard Mode is on — this rule is locked until the block ends" notice on the
overlay (the `canEdit` gate). Since `canPause` is false under Hard Mode, no Pause
control is shown — the locked block presents only the notice.

### Behavior change to call out

Open-limit rules were previously unblockable (the old `canUnblock` allowed any
kind, so a spent open-limit block could be lifted for the rest of the day). They
are now **not pausable at all**, per the table above.

## 3. Approach

Reuse the existing `pausedUntil` primitive and add a one-shot DeviceActivity
re-arm modeled on the **granted open session**.

`BlockingRule.pausedUntil` (mirrored to `RuleSnapshotDTO.pausedUntil`) already
drives `RuleActivation`: when a rule *would* block but `pausedUntil > now`, it
reports `.paused(until: min(pausedUntil, end))`, otherwise `.active`
(`RuleActivation.swift`). So once `pausedUntil` passes, the **derived** status
flips back to blocking on its own — no new state machine is needed. The only new
machinery is the background timer that re-applies the *shield* at the 15-minute
mark while the app is closed.

*Rejected alternatives:* foreground-reconciliation-only (no reliable background
re-block); a separate "pause session" store (redundant — `pausedUntil` already
models exactly this).

## 4. Components

### 4.1 Policy — `RulePolicy` (pure, unit-tested)

Rename and extend the existing gate:

- `unblock` → `pause`, `canUnblock` → `canPause`, add `resume`.
- `canPause(snapshot, usage, at, calendar)` returns true iff
  `activation(...) == .active(until: end)` **and** `!hardMode` **and**
  `kind ∈ {schedule, timeLimit}` **and** `end − now > temporaryPauseMinutes`.
- `pause(rule, at)` — guarded by `canPause`; sets a flat
  `rule.pausedUntil = now + temporaryPauseMinutes` (no longer `window.end` /
  `nextMidnight`). Returns false and changes nothing when not allowed.
- `resume(rule)` — sets `rule.pausedUntil = nil`.

Duration constant: `MonitoringPlan.temporaryPauseMinutes = 15`, sited next to
`openSessionMinutes` so the Screen-Time duration constants live together.

### 4.2 Status — `RuleStatus`

The `.paused` case's `label(relativeTo:)` changes from the static `"Paused"` to a
live countdown — `"Resumes in \(countdown(from: now, to: until))"` — reusing the
existing `countdown` formatter on the `.paused(until:)` date. `RuleActivation` is
unchanged. Verify the wording reads correctly everywhere `.paused` is rendered
(`rowContext`, `UsageDisplay.homeSubtitle`, the detail caption).

### 4.3 Background re-arm (new)

A one-shot `pause-<uuid>` DeviceActivity that re-shields when the pause ends —
structurally identical to the granted open session
(`ShieldActionExtension.startOpenSession` →
`DeviceActivityMonitorExtension.intervalDidEnd`).

- **`MonitoringPlan`**: add `pauseActivityName(for:) = "pause-" + uuid` and
  `ruleID(fromPauseActivityName:)`. The `pause-` prefix is distinct from
  `rule-` / `sched-` / `sched2-` / `tlwarn-` / `open-session-`, so no existing
  parser misclassifies it.
- **`ActivityMonitoring`** (+ `DeviceActivityCenterMonitor`, `MockActivityMonitor`):
  add a one-shot start, e.g. `startOneShotMonitoring(name:from:to:)`, mirroring
  `startOpenSession`'s `pauseMinutes + 1` interval padding (one extra minute keeps
  the interval above DeviceActivity's 15-minute floor; the `intervalDidEnd`
  re-shield fires at `pausedUntil + ~1 min`, after `pausedUntil`).
- **`RuleScheduler`**: `scheduleResumeReArm(for:until:)` starts the activity;
  `cancelResumeReArm(for:)` stops it. These are transient and are **not** part of
  `sync`'s `reconcile(plans)` (the re-arm is not derived from rule config). See
  §4.5 for how stale re-arms are reaped.
- **`RuleEnforcer`**: `pause(_:rules:)` and `resume(_:rules:)` orchestrate:
  - `pause`: `RulePolicy.pause` → `scheduler?.scheduleResumeReArm(for:until:)`
    → `refresh(rules:)` (clears the shield immediately). `pausedUntil` is set
    **before** `refresh`, so the just-started re-arm is not reaped in the same
    cycle (§4.5).
  - `resume`: `RulePolicy.resume` → `scheduler?.cancelResumeReArm(for:)` →
    `refresh(rules:)` (re-applies the shield immediately).

  The existing `expireStalePauseIfNeeded` (clears an elapsed `pausedUntil` during
  refresh) stays as the foreground safety net.

The detail overlay (§4.6) gains a `@Query` of rules so it can call
`enforcer.pause(rule, rules:)` / `resume(rule, rules:)` for the immediate shield
change (relying on the 30s loop would leave the app blocked for up to 30s after a
pause).

### 4.4 Monitor extension — `DeviceActivityMonitorExtension`

Handle the `pause-<uuid>` activity by running a **kind-dispatched reconcile on
both interval edges**, then stopping the one-shot at the end:

- `intervalDidStart` (fires ~immediately; rule is paused) → reconcile → clears
  the shield (a redundant safety clear; the foreground already cleared it).
- `intervalDidEnd` (pause elapsed; `isPaused` now false) → reconcile → re-shields
  if the rule is still blocking, then `DeviceActivityCenter().stopMonitoring`.

Dispatch by snapshot kind:

- schedule → `ScheduleEnforcement.reconcile(ruleID:)` (already clears/shields by
  enabled + `!isPaused` + window state).
- timeLimit → new `LimitEnforcement.handlePauseEnded(ruleID:)`, mirroring
  `handleOpenSessionEnded`: re-shield if `limitReached` **and** enabled **and**
  `scheduledToday` **and** `!isPaused`; else clear.

### 4.5 Clash resistance & re-arm lifecycle

**Isolation from other activities (no "undo").** Activities are keyed by
`DeviceActivityName`; a distinct `pause-` name is an independent registration,
so starting/stopping it never starts, stops, or replaces a rule's `rule-` /
`sched-` activities. Evidence in-repo:

- the open-session precedent runs a one-shot `open-session-<uuid>` concurrently
  with the open-limit rule's `rule-<uuid>` daily activity, stopping only the
  session at expiry;
- `reconcile`'s stale-activity stopper matches only `rule-` / `sched-` / `sched2-`
  / `tlwarn-` names (`RuleScheduler.swift`), so it never touches a `pause-`
  activity;
- `pause` changes no fingerprints (computed from kind/budget/selection/window,
  not `pausedUntil`), so the daily/window activities are never restarted — and a
  time-limit's usage-threshold accounting is never reset.

**Pause-awareness (they can't fight).** Every background re-shield path already
gates on `!isPaused(at:)` — `ScheduleEnforcement.reconcile`,
`LimitEnforcement.handleUsageMinutes` / `handleDayStart` / `handleOpenSessionEnded`.
So even if a `sched-`/`rule-` callback fires during the pause window, it clears or
drops rather than re-blocking.

**Re-arm lifecycle on external change (§3b).** A dangling re-arm is *correctness*-
safe on its own — when it fires it only recomputes from the current mirror and
can never create a block that shouldn't exist (it self-stops at `intervalDidEnd`).
But to respect the **20-activity ceiling** (`excessiveActivities`), stale re-arms
are reaped through the refresh funnel:

> In `RuleScheduler.sync`, after the normal reconcile, **stop** every monitored
> `pause-<uuid>` whose rule has `pausedUntil == nil` or no longer exists.

Properties of the reaping step:

- **Stop-only, never start.** The re-arm is started exactly once (by
  `enforcer.pause`); reaping must never restart it, or the 30s loop would keep
  pushing its interval forward and it would never fire.
- **Reap key is `pausedUntil == nil`, not `pausedUntil <= now`.** A naturally
  *expired* pause still has `pausedUntil` set (until `expireStalePauseIfNeeded`
  clears it), so reaping leaves it alone and lets the activity fire its background
  re-shield. Only *cancelled* pauses (disable / delete / resume / a pause-clearing
  edit) have `pausedUntil == nil` and are reaped.
- Covers all external-change paths through one funnel (`MainView` re-runs refresh
  on any rule change — its fingerprint already includes `pausedUntil`).
  `enforcer.resume` additionally cancels directly for immediacy.

Two documented caveats:

- **20-activity ceiling.** A pause consumes one slot transiently; starting the
  re-arm is best-effort (`try?`) like the open session, and the foreground
  reconciliation loop re-applies the block if a background start fails — worst
  case the background re-arm is missed, nothing else breaks.
- **Overlapping rules.** Pausing rule A lifts only A's shield; an app also
  covered by rule B stays blocked (strictest-wins, per the per-rule
  `ManagedSettingsStore` design). This is existing behavior — the old unblock had
  the identical property.

### 4.6 UI — `RuleDetailSheet`

Above the **Edit Rule** button, in the actions section:

- if the rule is currently paused → **Resume Blocking** (instant; no
  confirmation; e.g. `play.fill`), `accessibilityIdentifier`
  `resumeRuleButton`, calls `enforcer.resume(rule, rules:)`;
- else if `canPause` → **Pause for 15 minutes** (a plain button — **not**
  styled destructive, so its icon and title share the standard tint; e.g.
  `pause.circle`), `accessibilityIdentifier` `pauseRuleButton`, opens a
  `confirmationDialog` ("Apps unblock for 15 minutes, then blocking resumes
  automatically.") that calls `enforcer.pause(rule, rules:)`;
- else → nothing (just Edit Rule, or the Hard Mode lock notice).

The detail **"Unblocks allowed"** row is renamed to **"Pausing allowed"**, valued
honestly: `Yes` only when `kind != openLimit && !hardMode`, else `No` (so an
open-limit rule correctly reads `No`). Its `accessibilityIdentifier` becomes
`detailRow-Pausing allowed`.

### 4.7 UI — `HomeView` (Currently Blocking)

With Pause moved to the overlay, **Currently Blocking** rows become plain
navigational rows that open the detail overlay (matching the now-chevron-free
**Active Rules** rows; the chevron removal from `general-ui-improvements` is
already merged onto this branch). Remove the inline unblock dialog, the
"Hard Mode is on" alert, and the `unblockCandidate` / `hardModeBlockedAttempt`
state. No trailing chevron and no trailing lock badge. The
`blockedTile-<name>` identifier stays (tests rely on it).

### 4.8 Copy

`RuleEditorView`'s Hard Mode footer ("No unblocks allowed while the rule is
blocking.") is reworded to pause terminology (e.g. "This block can't be paused
while it's active.").

## 5. Documentation to update (same commit)

- Doc comments on every file whose behavior changes: `RulePolicy`, `RuleStatus`,
  `RuleActivation` (`.paused` comment), `BlockingRule.pausedUntil`,
  `RuleSnapshotDTO.isPaused`, `RuleEnforcer` ("soft unblock" mentions),
  `MonitoringPlan` (pause activity), `HomeView`, `RuleDetailSheet`.
- `AGENTS.md`:
  - Domain-facts **Hard Mode** bullet (replace "Soft rules can be 'unblocked',
    which sets `pausedUntil` = window end (the rule re-arms at its next window)"
    with the temporary-pause behavior).
  - Status enum line mentions `paused(until:)` — keep accurate.
  - Rules-feature-map row "Unblock / disable / delete / Hard Mode gating" →
    "Temporary pause / disable / delete / Hard Mode gating".
  - UI-test gotcha about the "unblock confirmation dialog" → pause dialog.
  - Key accessibility identifiers: add `pauseRuleButton` / `resumeRuleButton`;
    the `detailRow-Unblocks allowed` reference becomes `detailRow-Pausing allowed`.

## 6. Testing (TDD, red → green)

### Unit

- **`RulePolicy`**: `canPause` matrix — true for an actively-blocking soft
  schedule/time-limit rule with >15 min remaining; false for open-limit, for
  Hard Mode, when not blocking, when already paused, and when ≤15 min remains.
  `pause` sets `pausedUntil ≈ now + 15 min` for both supported kinds and is a
  no-op for excluded cases; `resume` clears `pausedUntil`.
- **`RuleStatus`**: `.paused` label renders the countdown ("Resumes in Xm").
- **`MonitoringPlan`**: `pauseActivityName` round-trips; `ruleID(fromPauseActivityName:)`
  rejects `rule-`/`sched-`/`tlwarn-`/`open-session-` names, and those parsers
  reject a `pause-` name.
- **`LimitEnforcement.handlePauseEnded`**: re-shields a spent, eligible
  time-limit; clears when paused / ineligible / not reached.
- **`RuleScheduler`**: `scheduleResumeReArm` starts a `pause-` activity (mock);
  `cancelResumeReArm` stops it; `sync` does **not** stop a still-paused rule's
  re-arm; `sync` **does** reap a `pause-` activity whose rule has
  `pausedUntil == nil` or no longer exists.
- **`RuleEnforcer`**: `pause` sets `pausedUntil`, schedules the re-arm, and clears
  the shield; `resume` clears `pausedUntil`, cancels the re-arm, and re-applies
  the shield; a `sched-`/usage callback delivered while paused leaves the shield
  cleared (isPaused gating).

### UI (rework existing)

- A **Currently Blocking** row tap opens the detail overlay (`detailRuleName`).
- Pause flow: active soft schedule rule shows **Pause for 15 minutes** → confirm
  → the rule becomes paused (drops into Active Rules, status "Resumes in …") →
  **Resume Blocking** appears → tap → it re-blocks.
- A Hard Mode active rule shows the lock notice and **no** Pause button.
- An active open-limit rule shows **no** Pause button.

Remove the now-obsolete unblock tests and `app.sheets.buttons["Unblock"]`
queries: `testUnblockActiveSoftRule`, `testHardLockedRuleCannotBeUnblocked`,
`testSoftRuleUnblockOfferedButHardRuleRefused`,
`testSpentBudgetCanBeUnblockedUntilTomorrow` (replace with their pause
equivalents).

## 7. On-device verification (pending, like the rest of Screen Time)

The simulator delivers no DeviceActivity callbacks, so the background re-arm
(`pause-<uuid>` `intervalDidEnd` re-shielding at ~15 min) is device-only. Verify
on device: pausing an active schedule/time-limit block clears the shield
immediately; the block returns ~15 min later without reopening the app;
**Resume Blocking** returns it instantly; disabling/deleting a rule mid-pause
leaves no `pause-` activity and no stray shield.
