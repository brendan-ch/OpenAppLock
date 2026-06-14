# OpenAppLock — "Rules" Feature Spec

This spec describes OpenAppLock's recurring app-blocking **rules** feature: the
behavior the app implements, then how it maps onto the native iOS presentation
(see §6).

---

## 1. Concept

A **Rule** is a recurring, automated app-blocking policy. Unlike a one-off
block/timer session, a rule re-arms itself on a schedule. Three rule types are
offered, presented on the "New Rule" sheet:

| Type | Icon | Example shown | Semantics |
|------|------|---------------|-----------|
| **Schedule** | calendar grid | "e.g. 9-5, Daily" | Block selected apps during a daily time window on chosen days |
| **Time Limit** | hourglass | "e.g. 45m/day" | After N minutes of cumulative use of selected apps per day, block them until a reset point |
| **Open Limit** | padlock | "e.g. 5 opens/day" | After N opens of selected apps per day, block them |

**Common attributes** — present for *every* rule kind:

- **Name** — user-editable, free text (presets: "Morning Focus", "Deep Work", "Evening Reset", "Lights Out", "Family Dinner", "Screen-Free Sunday"; defaults for new rules: "In the Zone" (schedule), "Time Keeper" (time limit))
- **Days of week** — 7-day toggle set, summarized as "Weekdays" / "Weekends" / "Every day" / custom
- **App List** *(OpenAppLock refinement)* — each rule points to exactly one
  **App List**: a named, reusable selection of apps/categories/websites stored
  independently of any rule. When editing a rule the user picks an existing
  list or creates a new one; editing a list affects every rule that uses it.
  Deleting a list detaches it from its rules (they fall back to "no apps").
- **Hard Mode** — boolean; subtitle "No unblocks allowed". When off, the rule detail shows "Unblocks allowed: Yes"
- **Enabled/disabled** — a rule can be disabled without deleting ("Disable Rule")

**Per-kind options** — each kind carries only the options that make sense for
it. The data model expresses this as a sum type (`RuleConfiguration`, see §5.2)
so a kind structurally cannot hold another kind's options:

- **Schedule** — a recurring **time window** (`From`/`To`, may cross midnight),
  a **Selection mode** (**Block** the list, or **Allow Only** = block
  everything except it; the mode belongs to the *rule*, not the list), and
  **Block Adult Content** (engage Screen Time's adult-website filter while the
  window is active).
- **Time Limit** — a **daily minutes budget**.
- **Open Limit** — a **daily opens budget**.

  Selection mode and Block Adult Content are **Schedule-only**: a usage budget
  over "everything except X" is not meaningful, and engaging a web-content
  filter when a *usage* budget is spent does not fit the feature. Time Limit and
  Open Limit rules are always Block and never touch the adult-content filter.

Derived status (drives card/detail UI):
- **Active** → countdown to window end: green pill "6h left"
- **Inactive** → countdown to next activation: "Starts in 22h" / "Starts in 11h"

---

## 2. Screen inventory & navigation map

```
Tab bar: [Home] [My Apps] [Timer]
                  │
                  ▼
            Apps screen (large title "Apps")
            ├── "Blocked Apps" section
            ├── "Rules >" section  ──ta p "+ New"──▶ New Rule sheet
            │        │                                 ├── tap rule-type card ─▶ Rule Editor (blank/default)
            │        │                                 └── tap preset card ───▶ Rule Editor (pre-filled)
            │        └── tap rule card ─▶ Rule Detail sheet
            │                               └── "Edit Rule" ─▶ Rule Editor (edit mode)
            │                                                    └── "Selected Apps >" ─▶ App Picker
            └── "Apps" section (folders: Distracting / Always Allowed / Never Allowed)
```

All rules UI is presented as **sheets stacked over the Apps screen** (dimmed,
blurred background; grabber at top; circular ✕ or ‹ button top-left). Nothing
navigates by push except within the sheet stack.

---

## 3. Screens in detail

### 3.1 Apps screen ("My Apps" tab)

Dark theme throughout (near-black background, very dark green tint).

1. **Large title** "Apps".
2. **Blocked Apps** — section header; horizontal row of currently-blocked app
   icons. Each icon has a lock badge overlay and a teal/green rounded-rect
   outline; caption "Unblock" under the icon. Tapping unblocks (with friction
   if hard mode).
   *(OpenAppLock)* Time/Open Limit rules whose budget is spent for the day
   also appear here, blocked until midnight.
3. **Usage** *(OpenAppLock addition)* — a section
   showing live tracking for every enabled Time/Open Limit rule scheduled today
   **that is not currently blocking**. Each row leads its subtitle with the rule
   **type** so the kind is clear without relying on the icon:
   - Time Limit row: subtitle "Time Limit · 18m of 45m used today", trailing "27m left".
   - Open Limit row: subtitle "Open Limit · 2 of 5 opens today", trailing "3 opens left".
   A rule whose budget is **spent** (actively blocking) **moves out of Usage into
   the "Currently Blocking" section** (it shows its type + usage there instead);
   a *soft-unblocked* spent rule is paused (not blocking), so it returns to Usage
   reading "Unblocked until tomorrow". Usage numbers come from the shared app-group
   ledger written by the DeviceActivity monitor and shield-action extensions.
3. **Rules** — header row: "Rules ›" (leading, tappable to a full list,
   presumably) and "**+ New**" (trailing, green tint) which opens the New Rule
   sheet.
   - Content: horizontally scrolling row of **rule cards** (~2 visible).
   - **Rule card** anatomy (rounded ~24pt corners):
     - Top: icon pair — rule-type icon (calendar) → small arrow → shield icon.
       Active rule: icons in color, card tinted dark green. Inactive: greyscale.
     - Middle: status — active: green capsule pill "6h left"; inactive: plain
       text "Starts in 22h".
     - Bottom: rule **name** (semibold), then a sub-row "Block" + tiny cluster
       of the blocked app icons.
4. **Apps** — section of folder-style groups: "Distracting (4 items)" showing
   a 2×2 mini icon grid, "Always Allowed", "Never Allowed (Hidden)" with an
   eye-slash glyph. (Out of scope for the rules clone but shares the app
   selection model.)

### 3.2 Rule Detail sheet

Presented on tapping a rule card. Partial-height card sheet.

- Top-left: circular ✕ close button.
- Centered: icon pair (rule type → shield), then caption
  "`Schedule, Starts in 22h`" (type + live status), then large title
  ("Weekend Zen").
- **Detail rows** (single inset rounded card, label left / value right):
  | Label | Example value |
  |---|---|
  | During this time | `09:00 – 12:00` |
  | On these days | `Weekends` |
  | Block | `[app icons] 1 App` / `3 Apps` |
  | Unblocks allowed | `Yes` (hidden/`No` when Hard Mode) |
- Bottom: full-width white pill button "**✎ Edit Rule**" → morphs the sheet
  into the Rule Editor in edit mode.

### 3.3 New Rule sheet

Presented from "+ New". Full-height sheet, scrollable.

- Header: ✕ left, centered title "**New Rule**".
- **Rule type row** — 3 horizontally arranged cards (Schedule / Time Limit /
  Open Limit), each: glyph, bold name, example caption ("e.g. 9-5, Daily",
  "e.g. 45m/day", "e.g. 5 opens/day"). Tapping opens the matching editor with
  defaults.
- **Preset gallery** — vertically scrolling sections, each with a bold header
  + grey subtitle, containing a 2-up grid of photo-backed preset cards:
  - **Focus Time** — "Protect your deep-work hours."
    - Morning Focus (Schedule 08:00–11:30, Block, weekdays)
    - Deep Work (Schedule 13:30–16:00, Block, weekdays)
  - **Rest & Recharge** — "Wind the day down on schedule."
    - Evening Reset (Schedule 21:00–23:00, Block)
    - Lights Out (Schedule 23:00–06:30, Block)
  - **Healthy Balance** — "Make room for what matters."
    - Family Dinner (Schedule 18:00–19:30, Block)
    - Screen-Free Sunday (Schedule 09:00–20:00, Block, Sundays)
  - **Preset card** anatomy: full-bleed background photo, top row icon pair
    (type → shield), time range caption, name, "Block" + suggested app icons,
    and a circular "+" button bottom-right. Tapping anywhere opens the
    Schedule editor pre-filled with the preset's name/times/days.

> **Navigation (OpenAppLock):** picking a rule type or preset **pushes** the
> editor inside the sheet via native SwiftUI navigation (`NavigationStack` +
> `navigationDestination(item:)`), so the system push animation and
> edge-swipe-back work; the editor keeps its custom header chrome.

### 3.4 Rule Editor — Schedule type

Sheet with: ‹ back (top-left), centered **rule name** as title, ✎ pencil
button (top-right) to rename.

Sections (each an inset rounded group with a small icon + caption header):

1. **📅 During this time**
   - Rows `From` / `To` with right-aligned time + stepper chevrons (`09:00 ⌃⌄`).
   - A dotted vertical line with ●/○ endpoints visually links From → To.
   - Tapping a row expands an inline wheel time picker (24h).
2. **On these days:** — trailing summary label ("Weekdays"/"Weekends"/custom);
   row of 7 circular toggles `S M T W T F S`; selected = filled white circle
   with black letter, unselected = dark circle.
3. **🛡 Apps are blocked**
   - Row: `App List` → `<list name> · N Apps ›` (or `Choose ›` when none) —
     presents the App List picker.
   - A segmented `Block | Allow Only` row (Schedule editor only) chooses how
     the rule interprets its list; the section header reads "Apps are
     blocked" / "Only these apps are allowed" accordingly.
4. **Hard Mode** `⚡PRO` badge — subtitle "No unblocks allowed"; trailing
   toggle.
5. **Block Adult Content** *(OpenAppLock addition; **Schedule rules only**)* —
   subtitle "Filter adult websites while this rule
   is active"; trailing toggle. Maps to Screen Time's web-content filter
   (`ManagedSettingsStore.webContent.blockedByFilter = .auto(...)`), applied
   and cleared together with the rule's shield. Surfaces in the rule detail
   as an "Adult websites | Blocked/Allowed" row. Time Limit and Open Limit
   editors do **not** offer this toggle (see §1, Per-kind options).
6. **CTA**
   - Creating: full-width gradient pill "**Hold to Commit**" — a press-and-hold
     interaction (deliberate friction) that fills, then saves and dismisses to
     the Apps screen where the new card appears.
   - Editing existing: "**✓ Done**" pill, plus a red text button
     "**⏸ Disable Rule**" beneath it.

### 3.5 Rule Editor — Time Limit type ("Time Keeper")

Same chrome (back / title / rename). Sections:

1. **⏳ When I use** — row `This App` → `Select ›` (app selection).
2. **For this long** — subtitle "Daily"; right-aligned value with stepper
   `45m ⌃⌄`.
3. **On these days:** — identical day picker as Schedule.
4. **🛡 Then block app** — row `Until` with stepper value `Tomorrow ⌃⌄`
   (reset point — e.g. tomorrow/next morning).
5. **Hard Mode** toggle — same as Schedule.
6. **Hold to Commit**. *(No Block Adult Content toggle — Schedule-only.)*

### 3.6 Rule Editor — Open Limit type

Spec by analogy with the other editors: "When I open [apps]" /
"More than `N opens ⌃⌄` (Daily)" / day picker / "Then block until …" /
Hard Mode / Hold to Commit. *(No Block Adult Content toggle — Schedule-only.)*

### 3.7 App Picker (shared component — also used in onboarding & timer)

Full-height sheet:

- Header: ‹ back, centered title "**Selected**", and a circular green **✓**
  confirm button top-right.
- **Segmented control**: `Block` | `Allow Only`.
- Top rows: "**+ Add App or Website**", a "Suggested" horizontal row of app
  icons (one-tap add), and a "Never Allowed — 0 Apps" row with footnote
  "Never allowed Apps will also be blocked".
- Hint text: *Select apps/websites, tap ">" to expand*.
- **Category list** — each row: circular checkbox (tri-state: empty /
  partially-selected count / checked), emoji glyph, category name, trailing
  selected-count + chevron to expand into individual apps:
  `All Apps & Categories, Social, Games, Entertainment, Creativity, Education,
  Health & Fitness, Information & Reading, Productivity & Finance,
  Shopping & Food`.
- **Search bar** pinned near bottom (with mic). Typing surfaces app matches
  and website suggestions (e.g. typing "insta" offers `instagram.com`),
  letting users add arbitrary domains.
- Footer: "**N Apps Selected**" caption + white pill "**Save**" (+ "Cancel").

> Implementation note: On iOS, third parties cannot enumerate installed apps;
> the system-sanctioned route is `FamilyActivityPicker` (FamilyControls), which
> provides its own category/app/website UI and returns opaque tokens. **v1 of
> OpenAppLock embeds `FamilyActivityPicker`** rather than a custom app picker.
>
> **App Lists (OpenAppLock):** the selection itself lives on a reusable
> **App List** (`@Model AppList`: name + encoded `FamilyActivitySelection`).
> The editor's App List row presents a picker sheet listing saved lists
> (checkmark on the rule's current list; tap to select), an Edit affordance
> per list, and a "New List" flow — a name field plus an embedded
> `FamilyActivityPicker`. The `Block`/`Allow Only` segmented control lives in
> the Schedule rule editor (it is rule state, not list state). Legacy rules
> that stored an inline selection are migrated at launch: one list per
> distinct selection (rules sharing identical selection data share a list),
> named "<rule name> Apps". Lists in use by a rule cannot be deleted from the
> picker. While any **Hard Mode** rule is actively blocking, all lists are
> read-only — the picker hides Edit/Delete and shows a lock notice — because
> editing a list would be a back door out of the hard block. Creating new
> lists and selecting lists for other rules remain available.

---

## 4. Behavioral spec

1. **Activation** — a Schedule rule becomes active at `From` on an enabled
   day and deactivates at `To` (windows crossing midnight, e.g. 23:00–06:30,
   must be supported — Lights Out preset does this).
2. **While active** — the rule's app selection is shielded (and, when the
   rule's Block Adult Content toggle is on, Screen Time's adult-website
   filter is engaged for the same span); blocked apps also
   surface in the "Blocked Apps" row on the Apps screen; the card turns green
   with a "Xh left" pill.
3. **Unblocking** — with Hard Mode off, the user may unblock mid-window
   ("Unblocks allowed: Yes"). With Hard Mode on, no unblocks until the window
   ends.
4. **Time-limit rules** — accumulate usage daily across the selected apps;
   on crossing the threshold, shield until the `Until` reset point
   (e.g. tomorrow), then reset the budget.
   *(OpenAppLock specifics)*: usage lives in a per-rule, per-day **usage
   ledger** in the app group. A limit rule's derived status becomes
   `active(until: next midnight)` once the ledger reports the budget spent on
   an enabled day — it then surfaces in Blocked Apps, Hard Mode gating
   applies, and a soft unblock pauses it until midnight. Open-limit rules
   work the same with an opens budget; while opens remain, their apps stay
   shielded with an "Open" button on the shield (each press spends one open
   and lifts the shield for up to 15 minutes — the DeviceActivity minimum
   interval). Because the shield is what *counts* opens, an enabled open-limit
   rule scheduled today is shielded **proactively from the start of the day,
   even before any opens are spent** — by *both* the background
   (`LimitEnforcement.handleDayStart`) and the foreground
   (`RuleEnforcer.refresh`) paths, so a freshly created open-limit rule gates
   its apps immediately and the gate survives the app being foregrounded. The
   one exception is a **granted "Open" session**: pressing Open lifts the
   shield for ~15 minutes, recorded as an expiry in the shared
   `OpenSessionStore`; while that session is live, neither path re-shields the
   rule (so the sanctioned session is never cut short), and the monitor
   re-shields when the session's one-shot activity ends. Unlike a *spent*
   budget, this proactive gate does **not** put the rule in "Blocked Apps"
   (which lists only rules whose budget is exhausted); it shows under "Usage"
   with its remaining opens.
5. **Disable vs delete** — "Disable Rule" pauses scheduling but keeps the
   rule (the card shows a disabled state). Delete is offered from the rule
   editor's actions menu.
6. **Commit friction** — creating/committing a rule uses press-and-hold
   ("Hold to Commit"), making the *start* of a commitment deliberate. Editing
   uses a plain "Done".
7. **Live countdowns** — "Starts in 22h" / "6h left" update over time
   (minute granularity is fine).
8. **Overlapping rules — strictest enforcement wins.** When several rules
   target the same app, the app is blocked if **any** of them is currently
   blocking it; rules never cancel each other out. This is structural rather
   than a resolved decision: each rule owns its own `ManagedSettingsStore`
   (`rule-<uuid>`), Screen Time **unions** shields across all stores, and a
   rule only ever writes/clears *its own* store. Consequences:
   - An open-limit and a time-limit rule on the same app each block via their
     own store, so whichever's budget is spent **first** blocks the app,
     regardless of the other's remaining budget.
   - An **Allow-Only** schedule cannot punch a hole for an app that another
     rule blocks: `.all(except:)` is itself a *shield* directive ("block
     everything except these"), not a whitelist that lifts other stores'
     shields. So if a schedule "allows" an app but a time limit blocks it, the
     time-limit block stands.
   - A soft **unblock** pauses only the one rule it was invoked on; other rules
     blocking the same app keep it blocked.

   There is deliberately **no** central merge of selections into a single
   shield set — such a merge would be the only place a block could be
   accidentally dropped.

---

## 5. Implementation plan for OpenAppLock

### 5.1 Frameworks & capabilities

- **FamilyControls** — `AuthorizationCenter.shared.requestAuthorization(for: .individual)`;
  `FamilyActivityPicker` + `FamilyActivitySelection` (app/category/web tokens).
- **ManagedSettings** — `ManagedSettingsStore` per rule
  (`ManagedSettingsStore.Name("rule-<uuid>")`); set
  `store.shield.applications` / `applicationCategories` / `webDomains`.
- **DeviceActivity** — `DeviceActivityCenter.startMonitoring` with a
  `DeviceActivitySchedule(intervalStart:intervalEnd:repeats:)` per rule;
  a **DeviceActivityMonitor app extension** applies/removes shields in
  `intervalDidStart`/`intervalDidEnd`. Time-limit rules use
  `DeviceActivityEvent(applications:threshold:)` +
  `eventDidReachThreshold`.
- Requires the **Family Controls entitlement** (works in dev; distribution
  needs Apple approval) and an App Group to share rule data with the monitor
  extension.

### 5.2 Data model (SwiftData)

The domain currency is a **sum type** so a rule can only hold the options that
belong to its kind — illegal states (e.g. an Open Limit rule with a time
window, or a Time Limit rule with Block Adult Content) are unrepresentable:

```swift
enum RuleKind: String, Codable { case schedule, timeLimit, openLimit }
enum SelectionMode: String, Codable { case block, allowOnly }

enum RuleConfiguration: Hashable, Sendable {
    case schedule(ScheduleConfig)
    case timeLimit(TimeLimitConfig)
    case openLimit(OpenLimitConfig)
    var kind: RuleKind { … }
}

struct ScheduleConfig: Hashable, Sendable {   // Schedule-only options
    var startMinutes: Int        // minutes from midnight, e.g. 540 = 09:00
    var endMinutes: Int          // may be ≤ start (crosses midnight)
    var selectionMode: SelectionMode
    var blockAdultContent: Bool  // webContent.blockedByFilter = .auto(...)
}
struct TimeLimitConfig: Hashable, Sendable { var dailyLimitMinutes: Int }
struct OpenLimitConfig: Hashable, Sendable { var maxOpens: Int }
```

The kind-common attributes (`name`, `days`, `hardMode`, `isEnabled`,
`appList`, `pausedUntil`) live alongside the configuration:

```swift
@Model final class BlockingRule {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var hardMode: Bool
    var appList: AppList?
    var days: [Int]              // 1...7, Calendar weekday numbers
    var pausedUntil: Date?
    var createdAt: Date
    // The kind-specific options, exposed as a computed bridge over the
    // model's raw stored columns:
    var configuration: RuleConfiguration { get set }
    var kind: RuleKind { configuration.kind }
}
```

`RuleDraft` (the editors' value-type working copy) carries the same
`configuration` + common fields, so each editor only renders its kind's
options. `BlockingRule` persists the configuration as flat columns and the
cross-process `RuleSnapshot` mirror keeps its flat wire shape; both are
read/written exclusively through the sum type. `FamilyActivitySelection` is
`Codable` → stored on the `AppList` as `Data`. Status ("active", "starts in
Xh", "Xh left") is **derived**, not stored.

### 5.3 View inventory

| View | Notes |
|---|---|
| `AppsView` (tab) | Sections: Blocked Apps, Rules carousel, (later) app folders |
| `RuleCardView` | Card per §3.1, active/inactive styling |
| `RuleDetailSheet` | §3.2, rows + Edit Rule |
| `NewRuleSheet` | §3.3, type cards + preset gallery (`RulePreset` static data) |
| `ScheduleRuleEditor` | §3.4 |
| `TimeLimitRuleEditor` | §3.5 |
| `DayOfWeekPicker` | 7 circle toggles + summary ("Weekdays"/"Weekends"/…) |
| `AppSelectionView` | wraps `FamilyActivityPicker`, Block/Allow Only segmented control |
| `HoldToCommitButton` | long-press progress fill, haptics, fires on completion |
| `RuleScheduler` (service) | translates `BlockingRule` ⇄ DeviceActivity monitoring |
| `ShieldController` (service) | applies/clears `ManagedSettingsStore` shields |

### 5.4 Suggested build order

1. Data model + Apps tab with Rules section (cards from seeded sample rules,
   status derivation, detail sheet) — pure UI, no entitlements needed.
2. New Rule sheet + Schedule editor + day picker + Hold to Commit (CRUD into
   SwiftData; Disable/Done editing path).
3. FamilyControls authorization + `FamilyActivityPicker` integration
   ("Selected Apps" row, "N Apps" counts, icon clusters via `Label(token:)`).
4. DeviceActivity monitor extension + ManagedSettings shields (real blocking,
   incl. midnight-crossing windows).
5. Time Limit editor + threshold events; Open Limit last (needs shield
   action extension + open counting).
6. Preset gallery content + polish (gradients, photos, haptics, live
   countdown timers).

### 5.5 Background enforcement architecture (implemented)

- **App group** `group.dev.bchen.OpenAppLock` shares four stores between the
  app and its extensions: `RuleSnapshotStore` (Codable rule mirror, written
  by `RuleScheduler` on every enforcement refresh), `UsageLedger` (per-rule,
  per-day minutes/opens), `OpenSessionStore` (per-rule expiry of a granted
  "Open" session), and the shield-store tracking list.
- **`RuleScheduler` (app)** reconciles DeviceActivity monitoring with the
  enabled rules:
  - **Limit rules** — one repeating 00:00–23:59 activity per rule
    (`rule-<uuid>`); time-limit rules carry one cumulative usage-threshold
    event per budget minute (`minutes-<k>`) over the rule's app list.
  - **Schedule rules** — one (or, for windows that cross midnight, two)
    repeating window activit(ies) per rule matching the rule's
    `From…To` window (`sched-<uuid>` and, for the post-midnight half,
    `sched2-<uuid>`). These carry no events; they exist purely to wake the
    monitor at the window edges so shields engage **in the background even
    when the app is closed**. A window that ends exactly at midnight, or is
    shorter than DeviceActivity's 15-minute minimum interval, may fail to
    register (`intervalTooShort`) and falls back to the foreground loop.
  Activities restart only when their configuration changes, because a
  restart resets threshold accounting.
- **`OpenAppLockMonitor`** (DeviceActivityMonitor extension): interval start
  = midnight reset for limit rules (open-limit rules re-shield so opens can
  be counted; time-limit shields clear for the fresh budget); each
  `minutes-<k>` event records usage and shields at the budget; a finished
  `open-session-<uuid>` one-shot re-shields after a granted open. For
  schedule-window activities (`sched-`/`sched2-`), **both** interval start
  and interval end **recompute** the rule's live schedule state from its
  snapshot (`RuleSchedule.isActive`, honouring enabled days, pause and the
  midnight-crossing rule) and apply or clear the shield accordingly — the
  same logic `RuleEnforcer.refresh` runs in the foreground, so the two paths
  agree.
- **Reliability posture** — DeviceActivity interval callbacks are
  "first device use after the boundary", are known to fire late or be
  skipped (device asleep, OS regressions on iOS 17/18/26), and a shield
  written over an app the user already has open may not visibly engage until
  that app is relaunched (a long-standing Screen Time platform limitation).
  Background monitoring is therefore **best-effort**; `RuleEnforcer.refresh`
  (launch + 30 s foreground loop) is retained as the reconciliation safety
  net and is the source of truth whenever the app runs. To keep that net
  consistent with the background, `refresh` applies the **same** open-limit
  proactive gate as `handleDayStart`: an enabled, scheduled-today, un-paused
  open-limit rule is shielded even before its budget is spent, *unless* the
  `OpenSessionStore` reports a still-running granted open for it — so the
  foreground loop establishes the turnstile for newly created rules and never
  re-locks an app mid-session.
- **`OpenAppLockShieldConfig`** (ShieldConfiguration extension): every shield
  carries the same generic **"App Blocked"** title — rule names are never shown,
  since the rule a shield is attributed to cannot be determined reliably when
  several rules cover the same app. Open-limit shields keep their functional
  detail under that title ("Opened X of N times today" with an "Open (Y left)"
  secondary button while opens remain); all other shields just read "This app is
  blocked by OpenAppLock." The text-only decision lives in the pure, unit-tested
  `ShieldPresentation` (in `Shared/`).
- **`OpenAppLockShieldAction`** (ShieldAction extension): the Open press
  spends one open in the ledger, lifts the rule's shield, records the session
  expiry in `OpenSessionStore`, and starts the ~15-minute one-shot session
  (DeviceActivity's minimum interval); the monitor clears that record when the
  session ends.
- All shared logic lives in `Shared/` (notably `LimitEnforcement`), unit
  tested from the app test target.

### 5.6 Out of scope (not part of "rules")

- Onboarding flow, paywall, Home tab gem/score UI, Timer tab (one-off focus
  sessions, "Leave Early?" friction screen), notification nudges ("Complete
  Your Setup").

---

## 6. Native UI re-skin (current presentation)

OpenAppLock has since replaced its custom themed presentation with the bare
iOS design language, keeping the backend (models, logic, services), the
flows, and the accessibility identifiers intact. Sections 1–5 remain as the
spec for *what* the feature does; presentation now maps as follows.

After onboarding the app is a three-tab `TabView` (`MainTabView`), each tab its
own `NavigationStack`:

```
TabView: [Home] [Rules] [Settings]
   │        │        └── "Uninstall Protection" toggle + "Manage App Lists" ─▶ App List library (management mode)
   │        └── rules grouped into Schedule / Time Limit / Open Limit sections; "+" ─▶ New Rule sheet
   │                 └── tap a rule row ─▶ Rule Detail sheet ─▶ "Edit Rule" ─▶ Rule Editor
   └── "Currently Blocking" section + "Usage" section
```

The app-level **enforcement lifecycle** (the `enforcer.refresh` 30 s loop, the
rule-change reconcile, and a scene-active reconcile) lives on `MainTabView`, so
it runs regardless of the selected tab.

| Spec element | Native presentation |
|---|---|
| Home tab | `NavigationStack` + `List`. **"Currently Blocking"** section (renamed from "Blocked Apps") — the *rules* blocking right now: **no leading icon**; a Hard Mode rule shows a trailing `lock.fill` (the block can't be lifted), a soft rule shows a trailing "Unblock" button; tapping a hard row shows the "Hard Mode is on" alert, a soft row the unblock dialog. A limit rule whose budget is **spent** appears here (moved out of Usage) with a `<Type> · <usage>` subtitle. **"Usage"** section: every enabled limit rule scheduled today that is *not* currently blocking, each row a `<Type> · NN of MM used today` subtitle + trailing remaining/blocked label. |
| Rules tab | `NavigationStack` + `List` split into **Schedule / Time Limit / Open Limit** sections (empty sections hidden); **rules are list rows** (leading kind icon, name, block summary, trailing live status — green when active); "+" toolbar button opens the New Rule sheet; tapping a row opens the Rule Detail sheet. |
| Settings tab | `NavigationStack` + `Form`. **Uninstall Protection** toggle — while on, the device's app-removal is denied (`ManagedSettingsStore.application.denyAppRemoval`) whenever any Hard Mode rule is actively blocking. **Manage App Lists** pushes the shared App List library in management mode (create / edit / delete, honoring the Hard Mode lock — same flow as the rule editor's picker, minus selection). |
| Rule detail | Sheet with inline nav title (name + "Schedule, 6h left" caption), `LabeledContent` rows, "Edit Rule" row pushes the editor; hard-locked rules show a lock row instead |
| New Rule | `List` with a "Rule Type" section and preset sections as plain rows; editor pushed via `navigationDestination(item:)` |
| Rule editor | Native `Form`: an inline **Name text field** at the top (no separate rename button; empty names fall back to the kind default), `DatePicker` rows, full-width day-circle row (≥44pt tap targets) with the summary in the section header, toggle rows with footers, stepper rows. Both modes commit via a **checkmark** in the navigation bar (labels: "Add Rule" / "Done"; replaces Hold to Commit). In edit mode an **ellipsis menu** ("Rule Actions") next to the checkmark holds Disable Rule and the destructive Delete Rule |
| Onboarding / app picker | System styling, `.borderedProminent` buttons, default color scheme (no forced dark, default accent) |

Dropped custom components: `Theme`, `HoldToCommitButton`, `RuleCardView`,
icon-pair/circle-button chrome.

### 6.1 Uninstall Protection (Settings)

A device-wide opt-in that makes Hard Mode harder to escape: while it is on **and**
any Hard Mode rule is actively blocking, the user cannot delete apps from the
device. `RulePolicy.shouldDenyAppRemoval(rules:enabled:usageFor:)` (= setting on
AND any rule `isHardLocked`) is the single gate; `RuleEnforcer.refresh` applies it
through `ShieldApplying.setAppRemovalDenied`, which sets
`ManagedSettingsStore(named: "uninstall-protection").application.denyAppRemoval`
(`true` to engage, `nil` to relinquish) on a **dedicated** store so per-rule
shield clears never touch it. The setting persists in the app-group defaults
(`uninstallProtectionEnabled`).

Enforced on the **foreground path only** for v1 (launch + 30 s loop + rule change
+ scene-active). Known limitation: a Hard Mode window that *ends* while the app is
closed leaves protection engaged until the app is next foregrounded — the safe
failure direction for a locker. Background recompute in the monitor extension is a
follow-up. Like all Screen Time behavior, the real device effect is only
observable on a device (the simulator uses mock shields).
