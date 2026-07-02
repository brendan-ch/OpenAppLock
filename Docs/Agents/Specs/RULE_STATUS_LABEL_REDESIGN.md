# Rule status-label redesign

Status: **Approved, not yet implemented** · Branch: `feat/conditional-status-row-time-limit`

Design spec for the copy and logic of the one-line "context" label rendered under
a rule's name across Home and the Rules tab, and as the rule-detail Status row.
Agent-managed (lives under `Docs/Agents/`). The behavior source of truth, once
implemented, is the doc comments on the owning source files (indexed by the
"Rules feature map" in `AGENTS.md`); this spec is the design rationale behind
those changes.

## 1. Motivation

Every rule row shows one live "context" line, produced by a single function —
`RuleSnapshotDTO.rowContext(for:usage:relativeTo:)` in
`OpenAppLock/Logic/RuleStatus.swift:77`. Its output is shared by four render
sites (see §2), so the wording of a given kind/state is uniform everywhere by
construction.

For **limit rules** (time-limit and open-limit) the current label is a poor fit:

- When not yet blocking it reads the daily budget ("45m / day", "5 opens / day")
  via `UsageDisplay.budgetPhrase(for:)`
  (`OpenAppLock/Logic/UsageDisplay.swift:24`) — a static allowance, not a live
  status. (Uncommitted WIP on this branch instead renders a bare "Running"
  placeholder; see §3.)
- When blocking it reads the static "Blocked until tomorrow"
  (`CopyKey.statusBlockedUntilTomorrow`, `RuleStatus.swift:86`).

Neither tells the user *when the situation changes*. A limit rule's budget resets
at tonight's midnight; a schedule rule's block ends at its window end. This
redesign makes every state read as a live countdown to its next transition,
worded per state.

## 2. Scope

One function: `RuleSnapshotDTO.rowContext(for:usage:relativeTo:)`
(`OpenAppLock/Logic/RuleStatus.swift:77`). The change is made once there and
applies uniformly to all four render sites — **no per-site divergence**:

| Site | Location |
|---|---|
| Home — "Currently Blocking" row | `OpenAppLock/Views/Home/HomeView.swift:69` (`blockingRow`), subtitle at `:81` (via `UsageDisplay.homeSubtitle`) |
| Home — "Active Rules" row | `OpenAppLock/Views/Home/HomeView.swift:122` (`activeRuleRow`), subtitle at `:134` (via `UsageDisplay.homeSubtitle`) |
| Rules tab row | `OpenAppLock/Views/Rules/RulesListView.swift:101` |
| Rule detail sheet — Status row | `OpenAppLock/Views/Rules/RuleDetailSheet.swift:354` (in `generalRows`) |

`UsageDisplay.homeSubtitle` (`UsageDisplay.swift:15`) prefixes the kind for the
two Home sites ("Time Limit · …"); it delegates the context string to
`rowContext`, so changing `rowContext` covers Home too.

## 3. Current behavior (pre-redesign starting point)

`rowContext` (`RuleStatus.swift:77-91`) branches on kind:

- **Schedule** → `status.label(relativeTo:)` (`RuleStatus.swift:26`), which maps
  `.active(until:)` → `CopyKey.statusActiveLeft` = `"%@ left"`,
  `.upcoming(startsAt:)` → `CopyKey.statusStartsIn` = `"Starts in %@"`,
  `.paused(until:)` → `CopyKey.statusResumesIn` = `"Resumes in %@"`,
  `.disabled` → `"Disabled"`, `.dormant` → `"No days selected"`. The countdown is
  formatted by `RuleStatus.countdown(from:to:)` (`RuleStatus.swift:38`).
- **Time Limit / Open Limit**:
  - `.disabled` / `.dormant` / `.paused` → `status.label(relativeTo:)` (shared
    with Schedule).
  - `.active` → `CopyKey.statusBlockedUntilTomorrow` = `"Blocked until tomorrow"`
    (`RuleStatus.swift:86`).
  - `.upcoming` → **uncommitted WIP** currently returns `CopyKey.statusRunning`
    = `"Running"` (`RuleStatus.swift:88`). The last committed state returned
    `UsageDisplay.budgetPhrase(for:)` ("45m / day" / "5 opens / day"). The WIP
    `"Running"` placeholder is superseded by this spec.

The doc comment on `rowContext` (`RuleStatus.swift:66-76`) still describes the
older "18m of 45m used" / "45m / day" budget wording and is stale relative to
even the committed code; it will be rewritten to match §4.

### Why the limit-rule states need new logic, not just new strings

For a limit rule, `status(...)` derives `.upcoming(startsAt:)` from
`RuleActivation.activation(...)` (`RuleActivation.swift:39`): when the rule is not
blocking, `nextStart` comes from `RuleSchedule.nextStart(after:)`
(`RuleSchedule.swift:48`), which finds the **next enabled day's** window start.

Limit rules carry a 0/0 "full day" window in their DTO
(`RuleSnapshotDTO.swift:22-24`), so today's window start (00:00) has always
already passed by the time anyone checks — `nextStart` therefore skips today and
returns the *next* enabled day's midnight. For an every-day rule that happens to
equal "tonight's midnight," which is why the mismatch has never been visible. But
for a partial-week rule (e.g. Mon/Wed/Fri) checked on an enabled day, `nextStart`
skips past tonight to the next enabled day — potentially days out. A "Resets in
{countdown}" label must **not** reuse that value.

## 4. New behavior

### Copy table

| Kind | State | Copy |
|---|---|---|
| Schedule | Disabled | "Disabled" (unchanged) |
| Schedule | No days selected | "No days selected" (unchanged) |
| Schedule | Paused | "Resumes in {countdown}" (unchanged) |
| Schedule | Active (blocking) | **"Ends in {countdown}"** — renamed from the current "{countdown} left" |
| Schedule | Upcoming | "Starts in {countdown}" (unchanged) |
| Time / Open Limit | Disabled | "Disabled" (unchanged, shared code path with Schedule) |
| Time / Open Limit | No days selected | "No days selected" (unchanged, shared code path) |
| Time / Open Limit | Paused | "Resumes in {countdown}" (unchanged, shared code path) |
| Time / Open Limit | **Scheduled today** — whether currently blocking (budget spent) or not (budget still available) | **"Resets in {countdown to tonight's midnight}"** — same text regardless of blocked state |
| Time / Open Limit | **Not scheduled today** | **"Starts in {countdown to the next enabled day}"** |

Notes on the shared-path rows:

- The **Paused** limit-rule row shares the Schedule code path. In practice it only
  ever fires for time-limit rules — `RulePolicy.canPause` excludes open-limit
  rules from pausing at all (see `TEMPORARY_PAUSE.md` §2) — but keeping the shared
  code path is still correct.

### Logic — the limit-rule branch of `rowContext`

Replace the `.active` / `.upcoming` cases of the `.timeLimit, .openLimit` branch
(`RuleStatus.swift:85-89`) with a single check keyed off
`RuleSnapshotDTO.isScheduledToday(at:)` (`RuleSnapshotDTO.swift:39`), **not** off
the `.active` / `.upcoming` distinction:

- **`isScheduledToday(at: now)` is true** — covers both the currently-blocking
  `.active` case *and* the not-yet-spent `.upcoming` case. (`activation` only ever
  returns `.active` for a limit rule when `isScheduledToday` is already true —
  `RuleActivation.swift:50` — so this single check captures both.) Compute
  `calendar.nextMidnight(after: now)` fresh — the same helper
  (`Calendar+NextMidnight.swift:11`) already used for the block's `blockEnd` at
  `RuleActivation.swift:52` — and render **"Resets in {countdown}"**.
- **`isScheduledToday(at: now)` is false** — the rule must be
  `.upcoming(startsAt:)` (a limit rule can never be `.active` on a day it isn't
  scheduled). `startsAt` (from the existing `nextStart` computation) is already
  correct here — render **"Starts in {countdown}"** against it.

The `.disabled` / `.dormant` / `.paused` limit-rule cases stay exactly as they
render today (shared with Schedule via `status.label(relativeTo:)`).

The Schedule branch changes only its one string: `.active(until:)` renders "Ends
in {countdown}" instead of "{countdown} left".

## 5. Rationale

- **Uniform content change, no per-site special-casing.** A limit-only divergence
  at the detail-sheet level — hiding the Status row entirely for time-limit rules
  — was tried and reverted earlier on this exact branch (commit `f6dbd2f` "Hide
  the 'Status' row for time limit rules", reverted by `a614faa`). That history is
  why this redesign changes the shared `rowContext` content once rather than
  special-casing any render site.
- **"Resets in {countdown}" is unified regardless of block state.** Whether the
  budget is spent (blocking) or still available (not blocking), a scheduled-today
  limit rule resets at tonight's midnight, so both read the same countdown. This
  is a deliberate simplification the product owner chose over showing distinct
  "Resets" / "Ends" wording depending on whether tomorrow is also a scheduled day.
- **Keep the live resume countdown for Paused.** "Resumes in {countdown}" is kept
  (not simplified to a bare "Paused") so a paused rule still names a real resume
  moment — consistent with the temporary-pause design (`TEMPORARY_PAUSE.md` §4.2).
- **Budget-at-a-glance is intentionally dropped.** See §6.

## 6. Scope decision — budget-at-a-glance removed

Before this change, Home's Active Rules row and the Rules tab row showed a limit
rule's daily budget (e.g. "45m / day", or per a stale doc comment "18m of 45m
used") via `UsageDisplay.budgetPhrase(for:)` (`UsageDisplay.swift:24`). This
redesign removes that display entirely in favor of the Resets/Starts countdown
copy in §4 — **there is no budget-amount display left anywhere `rowContext` is
rendered**. This is intentional, not an oversight.

## 7. Non-goals / deferred

- **The detail sheet's "Then block until: Tomorrow" row is left as-is.** For limit
  rules, `RuleDetailSheet`'s Details section already shows a "Then block until:
  Tomorrow" row (`ruleDetailThenBlockUntilRowLabel` + `ruleDetailTomorrowValue`,
  `RuleDetailSheet.swift:369` for time-limit and `:375` for open-limit). After
  this change the new Status row ("Resets in 8h") restates the same fact that row
  states, worded differently ("Then block until: Tomorrow"). The product owner has
  explicitly decided to leave this row unchanged for now and revisit separately.
  This duplication is noted for future reference only — do not change it as part of
  this work.

## 8. Implementation notes

### String Catalog changes

**New key.** Add `status.resetsIn` = `"Resets in %@"` (mirrors the existing
`status.startsIn` = `"Starts in %@"`). Add the `CopyKey` case in
`Shared/Copy/CopyKey.swift` (next to the other `status.*` keys,
~`CopyKey.swift:194-203`) and the localization entry in `Shared/Copy.xcstrings`.
Consume it the same way the existing countdown-based keys are — passing
`RuleStatus.countdown(from:to:)` as the `%@` argument.

**Value edit (no new key, no code change).** The Schedule Active relabel (§4) is a
catalog value change, not a new key: set `status.activeLeft`'s value in
`Shared/Copy.xcstrings` from `"%@ left"` to `"Ends in %@"`. The `statusActiveLeft`
case name is deliberately kept as-is, so `RuleStatus.label(relativeTo:)`
(`RuleStatus.swift:31`) already renders the new copy without any Swift change.

### Dead code to remove as part of implementation

- `UsageDisplay.budgetPhrase(for:)` (`UsageDisplay.swift:24-33`) — already has no
  callers in the current tree: the WIP at `RuleStatus.swift:88` (§3) replaced its
  last call site, and this redesign keeps it uncalled, so delete it.
- `CopyKey.usageMinutesPerDay` (`usage.minutesPerDay` = "%lldm / day") and
  `CopyKey.usageOpensPerDay` (`usage.opensPerDay` = "%lld opens / day") — the
  `CopyKey` cases (`CopyKey.swift:206-207`) and the `Shared/Copy.xcstrings`
  entries, once `budgetPhrase` is deleted.
- `CopyKey.statusBlockedUntilTomorrow` (`status.blockedUntilTomorrow` = "Blocked
  until tomorrow", `CopyKey.swift:202`) — the static label this replaces; remove
  the case and the catalog entry.
- `CopyKey.statusRunning` (`status.running` = "Running", `CopyKey.swift:203`) — the
  in-progress WIP placeholder currently sitting uncommitted in
  `RuleStatus.swift:88`. This spec supersedes it; remove the case and the catalog
  entry.

### Docs to update in the same change

Rewrite the stale `rowContext` doc comment (`RuleStatus.swift:66-76`) to describe
the §4 behavior, and refresh any `AGENTS.md` "Rules feature map" wording that
references the old budget/blocked-until labels.
