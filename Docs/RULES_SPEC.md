# OpenAppLock — Rules feature spec

This is the spec for OpenAppLock's recurring app-blocking **rules**. The detailed
behavioral and implementation prose now lives as **doc comments on the source it
describes** — open the file named for a topic below and the `///` comment at the
top of its primary type *is* the spec for that piece. This file is the **map**:
it holds the concept overview, the navigation/screen tree, the cross-cutting
invariants that have no single owning file, and a topic → source index so you can
jump straight to the code (and its spec) for any part of the feature.

> **Maintaining this spec.** It is human-owned and co-maintained by humans and
> agents (see [AGENTS.md](../AGENTS.md) → Documentation). When you change a
> behavior, update the doc comment on the file that owns it — that *is* the spec
> now — in the **same commit** as the code. Adjust the map below if a topic moves
> to a different file.

---

## §1 Concept

A **Rule** is a recurring, automated app-blocking policy. Unlike a one-off
block/timer session, a rule re-arms itself on a schedule. Three kinds exist:

| Kind | Example | Semantics |
|------|---------|-----------|
| **Schedule** | "9–5, Daily" | Block selected apps during a daily time window on chosen days |
| **Time Limit** | "45m/day" | After N minutes of cumulative use per day, block until a reset point |
| **Open Limit** | "5 opens/day" | After N opens per day, block until a reset point |

**Common to every kind** — a user-editable **name**, a **days-of-week** set, an
**App List** (a named, reusable selection of apps/categories/websites that a rule
points at; editing a list affects every rule that uses it), **Hard Mode** (while
the rule is actively blocking it cannot be lifted, edited, or deleted), and an
**enabled/disabled** flag.

**Per-kind options** are modelled as a sum type so a rule can only hold the
options that belong to its kind — illegal states are unrepresentable:

- **Schedule** — a recurring time **window** (may cross midnight), a **selection
  mode** (**Block** the list, or **Allow Only** = block everything except it),
  and **Block Adult Content** (Screen Time's adult-website filter).
- **Time Limit** — a daily **minutes** budget.
- **Open Limit** — a daily **opens** budget.

Selection mode and Block Adult Content are **Schedule-only** (rationale in
`RuleConfiguration`). Status ("6h left", "Starts in 22h", live usage) is always
**derived**, never stored.

→ Documented in: `Shared/RuleConfiguration.swift`, `Shared/RuleKind.swift`,
`OpenAppLock/Models/BlockingRule.swift`, `OpenAppLock/Models/RuleDraft.swift`,
`OpenAppLock/Logic/RuleStatus.swift`.

---

## §2 Navigation & screens (current native presentation)

After onboarding the app is an **adaptive shell** (`MainView`): a bottom
`TabView` in compact width (iPhone, iPad multitasking / Slide Over) and a
left-sidebar `NavigationSplitView` in regular width (full-screen iPad). Section
labels and icons come from a single `AppSection` enum so the two layouts can't
drift.

```
MainView (adaptive)                                       source
├── Home      "Currently Blocking" + "Usage"              HomeView
├── Rules     rules grouped Schedule / Time Limit /       RulesListView
│             Open Limit; "+" opens New Rule                ├─ NewRuleSheet → RuleEditorView
│             tap a rule opens its detail                    └─ RuleDetailSheet → RuleEditorView
└── Settings  Uninstall Protection, Manage App Lists,     SettingsView
              About links                                    └─ ManageAppListsView → AppListLibraryView
```

App pickers embed the system `FamilyActivityPicker` (third parties cannot
enumerate installed apps). The enforcement lifecycle — a 30 s refresh loop plus a
reconcile on rule changes and on scene-active — lives on `MainView`, so it runs
in either layout.

---

## Where each topic is documented

Each row points to the file whose doc comment holds the spec for that topic.

| Topic | Source (doc comment) |
|---|---|
| Rule kinds, sum-type options, Schedule-only rationale | `Shared/RuleConfiguration.swift`, `Shared/RuleKind.swift` |
| Persisted rule + common attributes | `OpenAppLock/Models/BlockingRule.swift` |
| Editor working copy (draft) | `OpenAppLock/Models/RuleDraft.swift` |
| Cross-process rule mirror | `Shared/RuleSnapshot.swift` |
| Derived status & countdown labels | `OpenAppLock/Logic/RuleStatus.swift` |
| Day-of-week picker & summary | `OpenAppLock/Views/Components/DayOfWeekPicker.swift`, `Shared/Weekday.swift` |
| Preset gallery | `OpenAppLock/Models/RulePreset.swift`, `OpenAppLock/Views/Rules/NewRuleSheet.swift` |
| Rule editors (all three kinds) | `OpenAppLock/Views/Rules/RuleEditorView.swift` |
| Rule detail sheet | `OpenAppLock/Views/Rules/RuleDetailSheet.swift` |
| App lists (model, picker, library, edit) + legacy migration | `OpenAppLock/Models/AppList.swift`, `OpenAppLock/Views/AppLists/*`, `OpenAppLock/Services/AppListMigration.swift` |
| Home: Currently Blocking + Usage, row strings | `OpenAppLock/Views/Home/HomeView.swift`, `OpenAppLock/Logic/UsageDisplay.swift` |
| Schedule activation / time-window math (incl. midnight crossing) | `Shared/RuleSchedule.swift`, `Shared/ScheduleEnforcement.swift` |
| Unblock / disable / delete / Hard Mode gating | `OpenAppLock/Logic/RulePolicy.swift` |
| Foreground shield reconciliation (source of truth while open) | `OpenAppLock/Services/RuleEnforcer.swift` |
| Time/open-limit behavior, granted opens, proactive gate | `Shared/LimitEnforcement.swift`, `Shared/UsageLedger.swift`, `Shared/OpenSessionStore.swift` |
| Shield application (per-rule `ManagedSettingsStore`) | `Shared/ShieldController.swift` |
| Shield text (never names a rule) + "Open" button | `Shared/ShieldPresentation.swift`, `OpenAppLockShieldConfig/ShieldConfigurationExtension.swift` |
| "Open" press handling | `OpenAppLockShieldAction/ShieldActionExtension.swift` |
| DeviceActivity scheduling, activity/event naming | `OpenAppLock/Services/RuleScheduler.swift`, `Shared/MonitoringPlan.swift` |
| Background monitor reactions (interval edges, thresholds) | `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift` |
| Uninstall Protection (§6.1) | `OpenAppLock/Views/Settings/SettingsView.swift`, `Shared/UninstallProtectionPolicy.swift`, `Shared/UninstallProtectionEnforcer.swift`, `OpenAppLock/Services/AppSettings.swift` |
| About links — GitHub / Website (§6.2) | `OpenAppLock/Services/AppLinks.swift`, `OpenAppLock/Services/LaunchConfiguration.swift` |

---

## §4.8 Overlapping rules — strictest enforcement wins

When several rules target the same app, the app is blocked if **any** of them is
currently blocking it; rules never cancel each other out. This is structural
rather than a resolved decision: each rule owns its own `ManagedSettingsStore`
(`rule-<uuid>`), Screen Time **unions** shields across all stores, and a rule
only ever writes/clears *its own* store. Consequences:

- An open-limit and a time-limit rule on the same app each block via their own
  store, so whichever's budget is spent **first** blocks the app, regardless of
  the other's remaining budget.
- An **Allow-Only** schedule cannot punch a hole for an app that another rule
  blocks: `.all(except:)` is itself a *shield* directive ("block everything
  except these"), not a whitelist that lifts other stores' shields. So if a
  schedule "allows" an app but a time limit blocks it, the time-limit block
  stands.
- A soft **unblock** pauses only the one rule it was invoked on; other rules
  blocking the same app keep it blocked.

There is deliberately **no** central merge of selections into a single shield
set — such a merge would be the only place a block could be accidentally dropped.
The invariant is exercised by `OpenAppLockTests/RuleEnforcerTests.swift`.

---

## Background enforcement architecture

**Frameworks & capabilities.** FamilyControls (authorization +
`FamilyActivityPicker` / `FamilyActivitySelection` opaque tokens), ManagedSettings
(one `ManagedSettingsStore` per rule, `rule-<uuid>`; a dedicated
`uninstall-protection` store), and DeviceActivity (a per-rule schedule registered
by `RuleScheduler`; time limits add `DeviceActivityEvent` usage thresholds).
Requires the **Family Controls entitlement** (works in dev; distribution needs
Apple approval for the app and each extension bundle id) and the **App Group**
`group.dev.bchen.OpenAppLock`, which carries `RuleSnapshotStore` (rule mirror),
`UsageLedger` (per-day minutes/opens), `OpenSessionStore` (granted-open expiry),
and the shield-store tracking list.

**Two enforcement paths that must agree.**

- **Foreground** — `RuleEnforcer.refresh` (launch + 30 s loop + rule change +
  scene-active) recomputes every shield from scratch and is the source of truth
  while the app runs.
- **Background** — `RuleScheduler` keeps DeviceActivity monitoring in step;
  `OpenAppLockMonitor` reacts at interval start/end and usage thresholds;
  `LimitEnforcement` and `ScheduleEnforcement` hold the shared reactions so both
  paths converge on the same shield state.

**Reliability posture.** DeviceActivity interval callbacks fire on "first device
use after the boundary", are known to arrive late or be skipped (device asleep,
OS regressions across iOS 17/18/26), and a shield written over an app the user
already has open may not visibly engage until that app is relaunched (a
long-standing Screen Time limitation). Background monitoring is therefore
**best-effort**, with the foreground loop as the reconciliation safety net. Real
Screen Time effects are only observable **on a device** — the simulator uses mock
shields and delivers no DeviceActivity callbacks.

---

## Out of scope (not part of the rules feature)

Paywall, the Home gem/score UI, a Timer tab (one-off focus sessions with a
"Leave Early?" friction screen), and notification nudges. The onboarding /
Screen Time permission flow exists (`OpenAppLock/Views/Onboarding/`) but is not
part of this spec.

---

## Appendix — original custom-design reference (pre-reskin, historical)

OpenAppLock originally shipped a **custom themed presentation** (near-black
background, dark-green tint) that has since been replaced by the bare native iOS
design language above; the backend, flows, and accessibility identifiers were
kept. This appendix records the original design intent so it isn't lost (the full
pre-rename document is in git history as `Docs/AGENT_RULES_FEATURE_SPEC.md`):

- **Tab bar** `[Home] [My Apps] [Timer]`; the rules lived on an "Apps" screen
  with a **Blocked Apps** row, a horizontally-scrolling **rules carousel** of
  rounded **rule cards** (rule-type icon → shield icon, a green status pill, name
  + blocked-app cluster), and folder-style app groups (Distracting / Always
  Allowed / Never Allowed).
- **Rules UI as stacked sheets** over the Apps screen (grabber, circular ✕/‹),
  rather than the current native push navigation.
- **New Rule sheet** with three rule-type cards and a **preset gallery** of
  photo-backed cards (Morning Focus, Deep Work, Evening Reset, Lights Out, Family
  Dinner, Screen-Free Sunday) — now plain list rows.
- **Schedule editor** with a dotted From→To connector and inline wheel time
  pickers; a custom **App Picker** with a tri-state category list and a bottom
  search bar (now the system `FamilyActivityPicker`).
- **"Hold to Commit"** — a press-and-hold gradient button that added deliberate
  friction to *creating* a rule (editing used a plain "Done"). Replaced by a
  navigation-bar checkmark.

Dropped custom components: `Theme`, `HoldToCommitButton`, `RuleCardView`, and the
icon-pair / circle-button chrome.
