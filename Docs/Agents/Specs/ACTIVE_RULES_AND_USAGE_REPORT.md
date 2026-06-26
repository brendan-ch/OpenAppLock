# Active Rules section + per-rule DeviceActivityReport

Status: **Implemented** (2026-06-25) — full test suite green (332/332); on-device
validation of the report rendering (Task 7) still pending (simulator cannot
exercise DeviceActivityReport).

## Motivation

The Home screen's "Usage" section shows a live "Xm of Ym used" counter for
time-limit rules. On device this counter does not track usage: it reads 0 for
the whole active window, then jumps straight to the budget when the block fires.

Root cause (verified from device logs): the live number was meant to come from
the `OpenAppLockReport` DeviceActivityReport extension writing an "authoritative"
daily total into `UsageLedger` (App Group `UserDefaults`). A DeviceActivityReport
extension is sandboxed **by design** so it cannot write to shared `UserDefaults`,
the network, or shared containers (Apple DTS, Developer Forums thread 728044) —
enforced on device, not on the Simulator. So the write-back never lands, and the
display falls back to the threshold count, which is a single `minutes-<budget>`
event (0-until-block). Blocking still enforces correctly; only the number is wrong.

The supported way to render real Screen Time activity is to display it **inside**
a `DeviceActivityReport` view that the app embeds — the extension renders its own
view; the host only ever receives a black-box view, never the raw numbers.

This change removes the broken counter, repurposes the report extension from a
(dead) ledger writer into a renderer, and embeds it in the rule-detail overlay so
we can evaluate how well an on-device `DeviceActivityReport` works.

## Goals

- Remove the "Xm of Ym used" live count everywhere on Home and in the rule-detail
  caption (no live usage number outside the new report).
- Rename Home's "Usage" section to "Active Rules", make its rows tappable to open
  the existing rule view/edit overlay (`RuleDetailSheet`), and broaden membership
  to include schedule rules whose next start is within 24h.
- Embed a per-rule `DeviceActivityReport` in `RuleDetailSheet` that renders the
  rule's combined app usage for today ("1h 12m today"); blank when there is no
  Screen Time data.
- Fully remove the now-dead "authoritative usage" machinery.

## Non-goals

- UI-testing the new report screen (it is device-only and unmockable; see Testing).
- A rich per-app usage visualization. v1 renders a single total line — a harness
  to evaluate whether the report works on device.
- Any change to enforcement (the `minutes-<budget>` block event is unchanged).

## Design

### 1. Home reshape — `OpenAppLock/Views/Home/HomeView.swift`

Two sections remain.

- **Currently Blocking** — unchanged membership (enabled rules whose live status
  is `.active`).
- **Active Rules** (renamed from "Usage") — membership becomes enabled rules that
  are **not** currently blocking, where:
  - **limit rules** (time/open): scheduled today (existing `isScheduledToday`
    filter), shown with their budget;
  - **schedule rules**: included only if their next start is **within the next 24
    hours** (status `.upcoming(startsAt:)` with `startsAt − now ≤ 24h`), shown
    with their next-start label.
  - Disabled rules excluded.

  Rows become `Button`s that open `RuleDetailSheet` for the tapped rule, presented
  with `.sheet(item:)` (the same pattern `RulesListView` uses). Row subtitle comes
  from the existing `rowContext` (schedules → "Starts in 22h"; limits → budget).
  Accessibility id `usageRow-<name>` is renamed to `activeRuleRow-<name>`.

### 2. Display-string cleanup — `OpenAppLock/Logic/UsageDisplay.swift`, `OpenAppLock/Logic/RuleStatus.swift`

- Delete `UsageDisplay.usagePhrase` (the "Xm of Ym used" / "N of M opens" string).
- `RuleSnapshotDTO.rowContext` limit branch loses the `usedToday` /
  `effectiveMinutesUsed` check:
  - `.upcoming` (under budget) → `UsageDisplay.budgetPhrase` ("45m / day",
    "5 opens / day");
  - `.active` (budget spent → blocking) → new short label **"Blocked until
    tomorrow"** (matches the detail row "Then block until: Tomorrow");
  - `.disabled` / `.dormant` / `.paused` → `status.label` (unchanged).
- Schedule branch unchanged (`status.label`).
- `UsageDisplay.budgetPhrase` and `homeSubtitle` unchanged.

Net: "Xm of Ym used" appears nowhere — not on Active Rules rows, the Currently
Blocking tile, or the `RuleDetailSheet` caption.

### 3. Authoritative-path full removal

No on-device behavior change: the authoritative figure was provably never written
on device, so `effectiveMinutesUsed` already always returned `minutesUsed`.

> Note (post-merge of origin/main, PR #26 DTO migration): `RuleUsage` is now
> `RuleUsageDTO` in `Shared/DTOs/RuleUsageDTO.swift` (the payload), with
> `UsageLedger` / `MockUsageLedger` both in `Shared/Stores/UsageLedger.swift` (the
> I/O). The authoritative fields live on the DTO; `recordAuthoritativeMinutes`
> lives on the ledger. Paths below reflect that split.

- `Shared/DTOs/RuleUsageDTO.swift`: remove `authoritativeMinutesUsed`,
  `authoritativeAsOf`, `effectiveMinutesUsed(asOf:)`, and `authoritativeFreshness`.
  `RuleUsageDTO` keeps `minutesUsed`, `opensUsed`.
- `Shared/Stores/UsageLedger.swift`: remove `recordAuthoritativeMinutes(...)`.
- `Shared/DTOs/RuleSnapshotDTO.swift` (`limitReached`, lines 48–53): use
  `usage.minutesUsed >= dailyLimitMinutes`.
- `OpenAppLock/Views/MainView.swift`: delete the invisible `ruleUsageReport`
  background view and its `usageFilter` (the dead writer host).
- `OpenAppLock/Services/RuleEnforcer.swift`: trim `logTimeLimitDecision` to a
  threshold-only log line (drop `auth=`/`source=`/the EC4 authoritative-undercount
  WARN, which can no longer occur).

### 4. Report extension → renderer; embed in the overlay

**Extension** — `OpenAppLockReport/`:
- Keep the `.ruleUsage` context (`Self("Rule Usage")`,
  `Shared/Platform/DeviceActivityReportContext.swift`) so the extension's
  Info.plist registration is unchanged; update its doc comment from "recompute
  authoritative usage" to "render the rule's usage".
- Replace `RuleUsageReportWriter` (ledger writer) with a renderer. The scene's
  `makeConfiguration(representing:) async -> String` sums `totalActivityDuration`
  across the handed `DeviceActivityResults` and returns a formatted total
  ("1h 12m today"); it returns an empty string when the total is zero / there is
  no data. `content: (String) -> some View` renders the string as `Text`, or
  `EmptyView` when the string is empty (the blank state).
- The extension no longer reads the App Group (no `RuleSnapshotStore` load); it
  renders whatever filtered data the host hands it. This sidesteps the question of
  whether the sandbox permits App Group reads.

**Host** — `OpenAppLock/Views/Rules/RuleDetailSheet.swift`:
- Add a "Usage" section (shown for all rule kinds) containing
  `DeviceActivityReport(.ruleUsage, filter:)`.
- The filter is built in the app from the rule's selection
  (`rule.appList?.selectionData` decoded via `AppSelectionCodec` into application
  / category / web-domain tokens) plus today's interval
  (`DateInterval(start: startOfDay, end: now)`), scoping the report to this one
  rule. The host passes scope in, so the extension stays identity-agnostic.
- Blank when there is no data (the extension renders `EmptyView`).

### 5. Testing & mocking

The report path cannot be mocked: `DeviceActivityReport` is a system view rendered
by the extension process, outside every existing mock seam
(`ScreenTimeAuthorization` protocol, `MockUsageLedger`, `MockShieldController`).
Real Screen Time data exists only on device, never in the Simulator/harness.

- **The new report screen is not UI-tested.** Gate the live `DeviceActivityReport`
  behind `LaunchConfiguration.current.isUITesting`: under `-ui-testing`,
  `RuleDetailSheet` renders the blank placeholder instead of instantiating the
  system view, so the extension never spins up during test runs. This matches the
  app's existing `isUITesting` branching in `OpenAppLockApp.init`. No new mock is
  added; the blank fallback is shared by (a) UI testing and (b) a real device with
  no usage yet.
- **Manual device validation** is the real signal (per AGENTS.md): on device, open
  a rule's detail and confirm the report renders a plausible "Xh Ym today" for the
  rule's apps, and renders blank when there is no usage.

**Test fallout to fix** (delete/adjust obsolete tests as the final refactor step):
- `OpenAppLockUITests/UsageUITests.swift`: rewrite — section header "Active Rules";
  rows show budget ("45m / day", "5 opens / day"); a spent limit shows "Blocked
  until tomorrow" in Currently Blocking; rows are tappable and open the detail
  overlay; identifiers `usageRow-*` → `activeRuleRow-*`. Remove all "Xm of Ym used"
  assertions.
- `OpenAppLockTests/UsageTests.swift`: delete the `usagePhrase` tests and
  `usagePhrasePrefersFreshAuthoritative` (authoritative removed); update
  `homeSubtitles` / `rowContext` expectations to budget / "Blocked until tomorrow".
- `OpenAppLockTests/RuleStatusTests.swift` (~line 153): update the "15m of 15m
  used" expectation to the new spent-limit wording.
- `MockUsageLedger` stays — it still drives which rules are blocking (`minutesUsed`)
  and open counts for the `-seed-scenario=limits` flows.

## File-by-file change summary

| File | Change |
|---|---|
| `OpenAppLock/Views/Home/HomeView.swift` | Rename Usage→Active Rules; new membership (24h schedule window); rows → buttons opening `RuleDetailSheet`; id `activeRuleRow-` |
| `OpenAppLock/Logic/UsageDisplay.swift` | Delete `usagePhrase` |
| `OpenAppLock/Logic/RuleStatus.swift` | `rowContext` limit branch → budget / "Blocked until tomorrow"; drop `usedToday` |
| `Shared/DTOs/RuleUsageDTO.swift` | Remove authoritative fields + `effectiveMinutesUsed` + `authoritativeFreshness` |
| `Shared/Stores/UsageLedger.swift` | Remove `recordAuthoritativeMinutes` |
| `Shared/DTOs/RuleSnapshotDTO.swift` | `limitReached` uses `minutesUsed` |
| `OpenAppLock/Views/MainView.swift` | Delete invisible report host + `usageFilter` |
| `OpenAppLock/Services/RuleEnforcer.swift` | Trim `logTimeLimitDecision` |
| `Shared/Platform/DeviceActivityReportContext.swift` | Update `.ruleUsage` doc comment |
| `OpenAppLockReport/RuleUsageReport.swift` | Scene returns `String`, renders text/EmptyView |
| `OpenAppLockReport/RuleUsageReportWriter.swift` | Replace writer with a duration-summing formatter (or fold into the scene) |
| `OpenAppLock/Views/Rules/RuleDetailSheet.swift` | Add per-rule `DeviceActivityReport` section; UI-testing gate; blank state |
| `OpenAppLockUITests/UsageUITests.swift` | Rewrite for Active Rules |
| `OpenAppLockTests/UsageTests.swift` | Delete usagePhrase/authoritative tests; adjust |
| `OpenAppLockTests/RuleStatusTests.swift` | Update spent-limit wording |

## Risks / things to watch on device

- Whether `DeviceActivityReport` renders at all when hosted in a sheet section
  (vs. the prior zero-size/opacity-0 host that may never have laid out). This is
  the core thing the change is meant to evaluate.
- `totalActivityDuration` includes Home-Screen/idle time per Apple's docs — the
  v1 total may read higher than expected; acceptable for a first pass.
- Report attribution covers application tokens reliably; category/web-domain
  attribution is less certain — note if a category-only rule renders blank.
- The report needs real FamilyControls authorization to render; `RuleDetailSheet`
  is only reachable post-onboarding, so production is fine.

## Decisions log

- Count removal scope: **everywhere, including the detail caption** — `usagePhrase`
  deleted.
- Cleanup scope: **full** — remove all authoritative machinery; `limitReached`
  uses `minutesUsed`.
- v1 report content: **total usage today**, per-rule filter.
- Active Rules membership: all kinds, not currently blocking; **schedules only if
  next start ≤ 24h**.
- Spent-limit label: **"Blocked until tomorrow"**.
- Report shown for **all rule kinds**.
