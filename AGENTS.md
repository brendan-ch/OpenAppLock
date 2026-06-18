# OpenAppLock — Agent Guide

OpenAppLock is an iOS Screen Time app: recurring **rules** that block selected
apps (Schedule windows, Time Limits, Open Limits), with a **Hard Mode** that
makes an active block impossible to lift, edit, or delete until it ends. The
presentation is bare native iOS (List/Form/NavigationStack, default color
scheme).

## Repo layout

```
OpenAppLock/                    App target (iOS 26, SwiftUI + SwiftData)
  Models/                   BlockingRule + AppList (@Model), RuleDraft,
                            RulePreset
  Logic/                    Pure, heavily unit-tested:
                            RuleStatus (derived status + labels, usage-aware),
                            RulePolicy (Hard Mode gating, unblock/pause,
                            app-list lock), UsageDisplay (Usage-section text)
  Services/                 ScreenTimeAuthorization (FamilyControls behind a
                            protocol + mock), RuleEnforcer (rules → shields),
                            RuleScheduler (rules → DeviceActivity monitoring),
                            AppListMigration, LaunchConfiguration +
                            SampleRules (UI-test harness)
  Views/                    Native SwiftUI screens (see Docs spec §6)
Shared/                     Compiled into the app AND all three extensions:
                            RuleKind, Weekday, RuleSchedule, AppGroup,
                            UsageLedger (per-day minutes/opens),
                            RuleSnapshot(+Store) (rule mirror in the app
                            group), MonitoringPlan (activity/event naming),
                            LimitEnforcement (shared event reactions),
                            ShieldController, ShieldLookup
OpenAppLockMonitor/         DeviceActivityMonitor extension: midnight resets,
                            usage-minute checkpoints → shield at the limit,
                            open-session expiry
OpenAppLockShieldConfig/    ShieldConfiguration extension: "Opened X of N" +
                            Open button on open-limit shields
OpenAppLockShieldAction/    ShieldAction extension: Open press spends an open,
                            lifts the shield, starts the ~15-min session
OpenAppLockTests/               Swift Testing unit suites (@MainActor — the app
                            target defaults to MainActor isolation)
OpenAppLockUITests/             XCUITest flows (see harness below)
Docs/AGENT_RULES_FEATURE_SPEC.md
                            Feature spec for the rules behavior; §6 maps it to
                            the native presentation. Source of truth — review
                            BEFORE behavior changes, keep current after them
                            (agent-managed; see Documentation).
Docs/AGENT_SWIFT_GUIDELINES.md
                            Swift coding/testing/patterns/security standards
                            agents must follow on this project (agent-managed).
```

## Documentation

Documentation splits into two buckets, distinguished by **filename**, not by
directory:

- **Agent-managed** — this `AGENTS.md`, `CLAUDE.md`, and any file whose name is
  prefixed with `AGENT_` (currently `Docs/AGENT_RULES_FEATURE_SPEC.md` and
  `Docs/AGENT_SWIFT_GUIDELINES.md`). Agents may **read, create, and edit** these
  and are expected to keep them accurate. Treat the feature spec as the source
  of truth for behavior, and update it when a behavior change makes it stale.
- **Human-authored** — every other doc, e.g. `README.md`. Agents may **read**
  these for context but must **never create or modify** them; flag needed
  changes for the maintainer instead.

The `AGENT_` prefix is the contract: it marks a file as safe for agents to
maintain. Any human-authored doc added without the prefix is automatically
off-limits to agent edits.

## Domain facts worth knowing

- Times are stored as **minutes from midnight**; `end <= start` means the
  window crosses midnight (e.g. 22:00→06:00) and belongs to the day it
  *starts* on. `start == end` = 24h window.
- Status is always **derived** (`rule.status(at:calendar:)`), never stored:
  `disabled / dormant / active(until:) / paused(until:) / upcoming(startsAt:)`.
  Countdown labels round hours **up** (e.g. "6h left").
- **Hard Mode**: `RulePolicy` is the single gate — while a hard-mode rule is
  actively blocking, canEdit/canDisable/canDelete/canUnblock are all false.
  Soft rules can be "unblocked", which sets `pausedUntil` = window end (the
  rule re-arms at its next window).
- Shields: one `ManagedSettingsStore` per rule (`rule-<uuid>`), tracked in
  UserDefaults for stray cleanup. `blockAdultContent` engages
  `webContent.blockedByFilter = .auto()` alongside the shield.
- `RuleEnforcer.refresh` is the only place shields change; the post-onboarding
  shell (`MainView`) runs it on rule changes and a 30s loop while the app is open,
  regardless of the active layout (compact `TabView` vs regular-width sidebar).

## Build & test

- Open `OpenAppLock.xcodeproj` in Xcode; build/test through the **Xcode MCP**
  tools (`BuildProject`, `RunAllTests`, `RunSomeTests` — get the tab id from
  `XcodeListWindows`). Make sure the scheme destination is an iOS
  **simulator**; a physical-device destination makes test runs hang or get
  cancelled.
- The project uses Xcode file-system-synchronized groups: adding/removing
  `.swift` files on disk is enough, no pbxproj editing.
- Family Controls entitlement is configured (`OpenAppLock/OpenAppLock.entitlements`).
  FamilyControls/ManagedSettings compile and run on the simulator, but real
  blocking behavior is only observable on a device.

## Workflow expectations (user preference)

These three are non-negotiable defaults — follow them on every task, not only
when reminded:

- **Always plan before execution.** Think through and lay out the approach (a
  written plan / plan mode for anything non-trivial) and confirm scope before
  editing code. Do not start changing files until the plan is clear.
- **Always use red-green TDD.** Consult `Docs/AGENT_RULES_FEATURE_SPEC.md`
  first for behavior changes — it is the source of truth. If a behavior change
  makes the spec inaccurate, keep it current (it is agent-managed; see
  Documentation above). Then write the failing test, run it (compile failure
  counts as red), implement, re-run focused tests, then the full suite. Run
  tests often and fail fast.
- **Always attempt to validate the UI manually before committing.** Build and
  run the app (simulator/device) and visually confirm the change behaves as
  intended. This step **may be skipped only when such tooling is unavailable**
  (e.g. the Xcode MCP / a simulator is not reachable in the session) — in that
  case, say so explicitly and hand the verification back to the user rather
  than silently skipping it.
- **Branch and open a PR for every change.** New features and bug fixes do not
  go directly onto `main`. Create a topic branch (`feat/…`, `fix/…`,
  `chore/…`), push it, and open a GitHub PR with `gh pr create` for the
  maintainer (brendan-ch) to review and merge themselves. `main` advances only
  through reviewed PRs. (The repository remains mirrored to `gitea`; GitHub is
  the review surface.)
- Conventional commits (`feat:`, `fix:`, `refactor:` …). **Agent attribution is
  required**: every commit an agent authors or co-authors must end with a
  `Co-Authored-By:` trailer naming the specific agent/model that did the work,
  added manually in the commit message — e.g.
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` (a
  non-Claude agent uses its own name/email). Commit only when the user asks.

## UI-test harness

`OpenAppLockApp` reads launch arguments (parsed by `LaunchConfiguration`):

| Argument | Effect |
|---|---|
| `-ui-testing` | In-memory SwiftData store, mock authorization, mock shields |
| `-onboarding-completed` / `-onboarding-required` | Force the onboarding flag |
| `-seed-scenario=standard` | Active soft rule "Work Time" + upcoming "Sleep" |
| `-seed-scenario=hard-mode-active` | Active Hard Mode rule "Locked In" + upcoming "Sleep" |
| `-github-url=<url>` / `-website-url=<url>` | Override the Settings About links with deterministic URLs |

Use `XCUIApplication.launchOpenAppLock(...)` (UITestSupport.swift), which also
provides `app.element(_:)` for identifier lookup across element types and
`waitToAppear()`.

Key accessibility identifiers (keep stable — tests and future work rely on
them): `newRuleButton`, `ruleCard-<name>`, `ruleStatus-<name>`,
`blockedTile-<name>`, `nothingBlockedLabel`, `emptyRulesCard`,
`closeNewRuleButton`, `ruleKind-<kind>`, `preset-<id>`, `ruleEditorTitle`,
`fromTimePicker`/`toTimePicker`, `dayToggle-1…7`, `selectedAppsRow`,
`hardModeToggle`, `adultContentToggle`, `dailyLimitStepper(+Value)`,
`maxOpensStepper(+Value)`, `commitRuleButton`, `doneButton`,
`toggleEnabledButton`, `deleteRuleButton`, `closeDetailButton`,
`detailRuleName`, `detailStatusLabel`, `detailRow-<label>`,
`hardModeLockedNotice`, `sidebarItem-<section>` (iPad sidebar rows: `home` /
`rules` / `settings`), settings About links: `githubLinkButton` /
`websiteLinkButton`, onboarding: `onboardingContinueButton`,
`allowScreenTimeButton`, `permissionDeniedLabel`, `openSettingsButton`.

Gotchas learned the hard way:
- **SwiftData relationships**: never assign a relationship property (e.g.
  `rule.appList`) inside a model's `init` or on un-inserted instances —
  insert both models into a context first, then wire them.
- **SwiftData container churn**: repeatedly creating `ModelContainer`s for
  this schema traps intermittently (EXC_BREAKPOINT inside SwiftData's
  configuration setup), which Xcode shows as a test "hang" paused at a
  breakpoint. Unit tests must go through `makeInMemoryContext()`
  (TestSupport.swift): one shared container per process, fresh context +
  data wipe per test.
- Identifiers on SwiftUI containers need `.accessibilityElement(children:
  .combine)` (or a Button/control) to be queryable.
- List/Form section headers render uppercased unless `.textCase(nil)` —
  tests assert exact header strings.
- Inside tinted Button rows, hierarchical `.primary`/`.secondary`/`.tertiary`
  foreground styles resolve to the tint (e.g. blue chevrons); use concrete
  `Color.primary`/`Color.secondary`/`Color(.tertiaryLabel)`.
- The unblock confirmation dialog is queried via `app.sheets.buttons[...]`
  (a bare `buttons["Unblock"]` is ambiguous with the row label).
- **iPad presentation differs and the UI suite runs on both** (CI matrix:
  iPhone + iPad). On iPad the shell is a sidebar, not a tab bar — navigate with
  the idiom-aware `goToHomeTab()/…` and `waitForMainUI()` helpers, never bare
  `tabBars`. Sheets present as *centered, shorter* form sheets, so: a window-edge
  swipe-back misses them (use the nav `BackButton`); rows can start below the
  fold (scroll into view); and span/width assertions measured against the full
  window only hold on iPhone (gate with `UIDevice.current.userInterfaceIdiom`).

## Known gaps / next steps

- **On-device verification of limit enforcement is pending.** The
  DeviceActivity monitor + shield extensions and the app group are in place,
  but real blocking/usage tracking is only observable on a device (the
  simulator neither tracks usage nor renders custom shields). Verify: time
  limits accrue in the Usage section and block at the budget; open-limit
  apps shield immediately with an "Open (N left)" button; an open lasts
  ~15 minutes (DeviceActivity's minimum interval) before re-shielding.
- **Schedule-rule background transitions** are now backed by DeviceActivity:
  `RuleScheduler` registers a repeating window activity per schedule rule
  (`sched-<uuid>`, plus `sched2-<uuid>` for midnight-crossing windows) and the
  monitor extension recomputes + applies/clears the shield on interval
  start/end. The foreground 30s loop remains as the reconciliation safety net
  because interval callbacks are unreliable. On-device verification of the
  background transition is still pending (the simulator does not deliver
  DeviceActivity callbacks).
- `FamilyActivityPicker` shows few apps on the simulator; fine on device.
- `FamilyActivityPicker` **silently ignores selections** (binding never
  updates, rows still show checkmarks) unless real FamilyControls
  authorization has been granted — in `-ui-testing` launches authorization
  is mocked, so picker selections can never be asserted in UI tests. To
  verify selection flows manually on the simulator, launch without
  `-ui-testing`, complete onboarding, and approve the system Screen Time
  prompts ("Allow with Passcode" works on the simulator).
- Distribution (App Store) requires Apple's approval for the Family Controls
  entitlement **for the app and each extension bundle ID**
  (`dev.bchen.OpenAppLock`, `.Monitor`, `.ShieldConfig`, `.ShieldAction`);
  development builds work with the dev entitlement.
