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
                            RulePolicy (Hard Mode gating, temporary pause,
                            app-list lock), UsageDisplay (Usage-section text)
  Services/                 ScreenTimeAuthorization (FamilyControls behind a
                            protocol + mock), RuleEnforcer (rules → shields),
                            RuleScheduler (rules → DeviceActivity monitoring),
                            AppListMigration, LaunchConfiguration +
                            SampleRules (UI-test harness)
  Views/                    Native SwiftUI screens (spec in each view's doc
                            comment; see "Rules feature map" below)
Shared/                     Compiled into the app AND all four extensions,
                            grouped by architectural layer:
  Models/                   Pure rule-domain value types: RuleKind,
                            RuleConfiguration, RuleSchedule, Weekday
  DTOs/                     Codable plain-data mirrors persisted to the app
                            group (the payloads the extensions read):
                            RuleSnapshotDTO (rule mirror), RuleUsageDTO
                            (per-day minutes/opens + authoritative daily total)
  Enforcement/              Stateless decisions + shield controllers that turn
                            rules/events into blocks: ScheduleEnforcement,
                            LimitEnforcement (shared event reactions),
                            LimitWarningDecision, UninstallProtectionPolicy,
                            UninstallProtectionEnforcer, ShieldController,
                            ShieldLookup, ShieldPresentation
  Stores/                   App-group persistence/accessors: UsageLedger
                            (reads/writes RuleUsageDTO per day), OpenSessionStore,
                            DayStartStore (confirmed daily-activity starts),
                            RuleSnapshotStore (writes the rule mirror),
                            NotificationPreferences
  Diagnostics/              Logging subsystem: DiagnosticLog (`Diag` dual-sink
                            logging facade) + LogEntry/LogMerge/LogRetention/
                            LogFileWriter (per-process daily log files in the
                            app group)
  Platform/                 OS-integration glue / shared identifiers:
                            AppGroup, MonitoringPlan (activity/event naming),
                            DeviceActivityReportContext
OpenAppLockMonitor/         DeviceActivityMonitor extension: midnight resets,
                            usage-minute checkpoints → shield at the limit,
                            open-session expiry
OpenAppLockShieldConfig/    ShieldConfiguration extension: "Opened X of N" +
                            Open button on open-limit shields
OpenAppLockShieldAction/    ShieldAction extension: Open press spends an open,
                            lifts the shield, starts the ~15-min session
OpenAppLockReport/          DeviceActivityReport extension: computes each
                            time-limit rule's true daily usage (foreground only)
                            and writes it to UsageLedger as the authoritative
                            figure
OpenAppLockTests/               Swift Testing unit suites (@MainActor — the app
                            target defaults to MainActor isolation)
OpenAppLockUITests/             XCUITest flows (see harness below)
Docs/AGENT_SWIFT_GUIDELINES.md
                            Swift coding/testing/patterns/security standards
                            agents must follow on this project (agent-managed).
Docs/Agents/                Agent working docs — the whole folder is
                            agent-modifiable. Design specs live under
                            Docs/Agents/Specs/ (agent-managed).
```

## Documentation

Documentation falls into three buckets:

- **Agent-managed** — this `AGENTS.md`, `CLAUDE.md`, any file whose name is
  prefixed with `AGENT_` (currently `Docs/AGENT_SWIFT_GUIDELINES.md`), and
  **anything under `Docs/Agents/`** (e.g. design specs in `Docs/Agents/Specs/`,
  plans in `Docs/Agents/Plans/`) — the folder marks ownership by location, so
  files inside it need no `AGENT_` prefix. Agents may **read, create, and edit**
  these and are expected to keep them accurate.
- **Shared (human + agent)** — the rules feature spec. It lives as doc comments
  **on the source each behavior owns**; both humans and agents maintain it. The
  doc comments are the source of truth for behavior — when you change a behavior,
  update the owning file's doc comment in the same commit. The "Rules feature
  map" section below indexes where each topic lives; keep it current when a topic
  moves to a different file.
- **Human-authored** — every other doc, e.g. `README.md`. Agents may **read**
  these for context but must **never create or modify** them; flag needed
  changes for the maintainer instead.

The `AGENT_` prefix marks a file as safe for agents to maintain; any other
un-prefixed doc remains off-limits to agent edits.

## Domain facts worth knowing

- Times are stored as **minutes from midnight**; `end <= start` means the
  window crosses midnight (e.g. 22:00→06:00) and belongs to the day it
  *starts* on. `start == end` = 24h window.
- Status is always **derived** (`rule.status(at:calendar:)`), never stored:
  `disabled / dormant / active(until:) / paused(until:) / upcoming(startsAt:)`.
  Countdown labels round hours **up** (e.g. "6h left").
- **Hard Mode**: `RulePolicy` is the single gate — while a hard-mode rule is
  actively blocking, canEdit/canDisable/canDelete/canPause are all false.
  Soft schedule/time-limit rules with >15 min left support a **Temporary Pause**
  (`RulePolicy.pause`): a 15-minute lift (`pausedUntil = now + 15m`), re-armed in
  the background by a one-shot `pause-<uuid>` DeviceActivity. Open-limit and
  Hard Mode rules can't be paused.
- Shields: one `ManagedSettingsStore` per rule (`rule-<uuid>`), tracked in
  UserDefaults for stray cleanup.
- `RuleEnforcer.refresh` is the only place shields change; the post-onboarding
  shell (`MainView`) runs it on rule changes and a 30s loop while the app is open,
  regardless of the active layout (compact `TabView` vs regular-width sidebar).

## Rules feature map

The feature behaves as documented in `///` doc comments **on the source each
topic owns** — this section is the map to them, not a second copy of the spec.
Concept and per-kind options live in `RuleConfiguration` / `RuleKind` /
`BlockingRule`; the load-bearing invariants are in "Domain facts" above.

Screens — post-onboarding adaptive shell (`MainView`: a tab bar in compact
width, a sidebar in regular-width iPad; section labels from one `AppSection`):

```
Home      Currently Blocking + Usage               HomeView
Rules     rules grouped by kind; + opens New Rule   RulesListView
            New Rule → editor                         NewRuleSheet → RuleEditorView
            tap a rule → detail → editor              RuleDetailSheet → RuleEditorView
Settings  Uninstall Protection, App Lists,           SettingsView → ManageAppListsView
            Notifications, About                       SettingsView → NotificationSettingsView
```

Where each topic is documented:

| Topic | Source (doc comment) |
|---|---|
| Rule kinds, sum-type options, Schedule-only rationale | `Shared/Models/RuleConfiguration.swift`, `Shared/Models/RuleKind.swift` |
| Persisted rule + common attributes; editor draft; cross-process mirror | `OpenAppLock/Models/BlockingRule.swift`, `OpenAppLock/Models/RuleDraft.swift`, `Shared/DTOs/RuleSnapshotDTO.swift` |
| Derived status & countdown labels | `OpenAppLock/Logic/RuleStatus.swift` |
| Day-of-week picker & summary | `OpenAppLock/Views/Components/DayOfWeekPicker.swift`, `Shared/Models/Weekday.swift` |
| Presets; editors (all kinds); detail | `OpenAppLock/Models/RulePreset.swift`, `OpenAppLock/Views/Rules/RuleEditorView.swift`, `OpenAppLock/Views/Rules/RuleDetailSheet.swift` |
| App lists (model, picker, library, edit) + legacy migration | `OpenAppLock/Models/AppList.swift`, `OpenAppLock/Views/AppLists/*`, `OpenAppLock/Services/AppListMigration.swift` |
| Home: Currently Blocking + Usage, row strings | `OpenAppLock/Views/Home/HomeView.swift`, `OpenAppLock/Logic/UsageDisplay.swift` |
| Schedule activation / time-window math (incl. midnight crossing) | `Shared/Models/RuleSchedule.swift`, `Shared/Enforcement/ScheduleEnforcement.swift` |
| Temporary pause / disable / delete / Hard Mode gating | `OpenAppLock/Logic/RulePolicy.swift` |
| Foreground reconciliation; **overlapping rules → strictest wins** | `OpenAppLock/Services/RuleEnforcer.swift`, `Shared/Enforcement/ShieldController.swift` |
| Time/open-limit behavior, granted opens, proactive gate | `Shared/Enforcement/LimitEnforcement.swift`, `Shared/Stores/UsageLedger.swift` (+ `Shared/DTOs/RuleUsageDTO.swift`), `Shared/Stores/OpenSessionStore.swift` |
| Shield text + "Open" button / press handling | `Shared/Enforcement/ShieldPresentation.swift`, `OpenAppLockShieldConfig/ShieldConfigurationExtension.swift`, `OpenAppLockShieldAction/ShieldActionExtension.swift` |
| DeviceActivity scheduling, naming; background monitor (time limits run **per-day day-keyed** activities) | `OpenAppLock/Services/RuleScheduler.swift`, `Shared/Platform/MonitoringPlan.swift`, `Shared/Models/ScheduledDayPlanner.swift`, `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`; design spec `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md` |
| Authoritative time-limit usage report; confirmed day-start gate | `OpenAppLockReport/RuleUsageReport.swift`, `Shared/Stores/DayStartStore.swift`, `OpenAppLock/Views/MainView.swift` |
| Uninstall Protection | `OpenAppLock/Views/Settings/SettingsView.swift`, `Shared/Enforcement/UninstallProtectionPolicy.swift`, `Shared/Enforcement/UninstallProtectionEnforcer.swift`, `OpenAppLock/Services/AppSettings.swift` |
| Notifications (permission + schedule-start & time-limit nudges) | `OpenAppLock/Views/Settings/NotificationSettingsView.swift`, `OpenAppLock/Services/NotificationAuthorization.swift`, `OpenAppLock/Services/NotificationScheduler.swift` (+ `ScheduleStartNotificationPlan.swift`), `Shared/Stores/NotificationPreferences.swift`, `Shared/Enforcement/LimitWarningDecision.swift`, `OpenAppLockMonitor/LimitWarningNotifier.swift`, `Shared/Platform/MonitoringPlan.swift` (`tlwarn-`/`warn-`); design spec `Docs/Agents/Specs/NOTIFICATIONS.md` |
| About links (GitHub / Website) | `OpenAppLock/Services/AppLinks.swift`, `OpenAppLock/Services/LaunchConfiguration.swift` |
| Diagnostic logging + daily export | `Shared/Diagnostics/DiagnosticLog.swift`, `Shared/Diagnostics/LogEntry.swift`, `Shared/Diagnostics/LogFileWriter.swift` (+ `LogMerge`/`LogRetention`), `OpenAppLock/Services/LogStore.swift`, `OpenAppLock/Views/Settings/DiagnosticLogsView.swift`; instrumentation lives at each enforcement site; design spec `Docs/Agents/Specs/DIAGNOSTIC_LOGGING.md` |
| User-facing copy (String Catalog, symbolic keys) | `Shared/Copy/CopyKey.swift`, `Shared/Copy.xcstrings`; design spec `Docs/Agents/Specs/COPY_STRING_CATALOG_MIGRATION.md` |

Not part of the feature: paywall, the Home gem/score UI, a Timer tab (one-off
sessions). Onboarding exists (`OpenAppLock/Views/Onboarding/`)
but is out of scope. The pre-reskin custom-themed design (Hold-to-Commit, rule
cards, photo preset gallery) is recoverable from git history
(`Docs/AGENT_RULES_FEATURE_SPEC.md`, removed when the spec was folded into code).

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
- **Always use red-green TDD.** Consult the feature spec first for behavior
  changes — the doc comment on the file you're changing is the source of truth,
  indexed by the "Rules feature map" above. If a change makes a doc comment
  inaccurate, update it in the same commit (see Documentation above). Then write
  the failing test, run it (compile failure counts as red), implement, re-run
  focused tests, then the full suite. Run tests often and fail fast.
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
| `-seed-logs` | Route diagnostic logs to a wiped per-launch temp dir and seed deterministic `SEED-MARKER` entries (Settings → Diagnostics → Logs export flow) |

Use `XCUIApplication.launchOpenAppLock(...)` (UITestSupport.swift), which also
provides `app.element(_:)` for identifier lookup across element types and
`waitToAppear()`.

Key accessibility identifiers (keep stable — tests and future work rely on
them): `newRuleButton`, `ruleCard-<name>`, `ruleStatus-<name>`,
`blockedTile-<name>`, `nothingBlockedLabel`, `emptyRulesCard`,
`closeNewRuleButton`, `ruleKind-<kind>`, `preset-<id>`, `ruleEditorTitle`,
`fromTimePicker`/`toTimePicker`, `dayToggle-1…7`, `selectedAppsRow`,
`hardModeToggle`, `dailyLimitStepper(+Value)`,
`maxOpensStepper(+Value)`, `commitRuleButton`, `doneButton`,
`toggleEnabledButton`, `deleteRuleButton`, `closeDetailButton`,
`pauseRuleButton`, `resumeRuleButton`,
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
- The pause confirmation dialog is queried via `app.sheets.buttons[...]`
  (a bare `buttons["Pause for 15 minutes"]` is ambiguous with the
  `pauseRuleButton` row label). Pause/Resume live on the rule detail overlay;
  Home's Currently Blocking rows navigate to it.
- **iPad presentation differs and the UI suite runs on both** (CI matrix:
  iPhone + iPad). On iPad the shell is a sidebar, not a tab bar — navigate with
  the idiom-aware `goToHomeTab()/…` and `waitForMainUI()` helpers, never bare
  `tabBars`. Sheets present as *centered, shorter* form sheets, so: a window-edge
  swipe-back misses them (use the nav `BackButton`); rows can start below the
  fold (scroll into view); and span/width assertions measured against the full
  window only hold on iPhone (gate with `UIDevice.current.userInterfaceIdiom`).

## Known gaps / next steps

- **Diagnostic logs are now the primary on-device instrument.** Every process
  logs how/when blocks execute to `os.Logger` (live in Xcode/Console) and to
  per-process daily files in the app group, exportable from Settings →
  Diagnostics → Logs as a per-day `.txt`. Each line carries its
  `[File.swift:line function]` so behavior traces back to code. When debugging
  the time-limit / blocking inconsistencies, pull a day's export and read the
  enforcement timeline (the `event`-level lines and the "drop … (stale …)"
  rejections in particular). Instrumentation breadth may widen after the first
  device logs. **Likely bug surfaced while instrumenting:** editing an existing
  app list saves the new selection but its editor completion handler is a no-op
  (`AppListLibraryView` `editingList` → `{ _ in }`), so nothing re-enforces
  until the next 30 s `RuleEnforcer` loop — a strong match for "app-list edits
  don't register after I save." Not fixed in the logging change; confirm via the
  logs (an `appList saved … (edit)` line with no following `enforcer refresh`)
  then address separately.
- **On-device verification of limit enforcement is pending.** The
  DeviceActivity monitor + shield extensions and the app group are in place,
  but real blocking/usage tracking is only observable on a device (the
  simulator neither tracks usage nor renders custom shields). Verify: time
  limits accrue in the Usage section and block at the budget; open-limit
  apps shield immediately with an "Open (N left)" button; an open lasts
  ~15 minutes (DeviceActivity's minimum interval) before re-shielding.
- **Time-limit counting hardening** (see
  `Docs/Agents/Specs/TIME_LIMIT_COUNTING_HARDENING.md`) is implemented but
  device-verification is pending. Time limits now register a **single**
  `minutes-<budget>` block event (not a per-minute chain); the monitor records
  usage only for rules eligible today and only after a **confirmed**
  daily-activity start (`DayStartStore`), dropping stale cross-midnight
  flushes. The new **`OpenAppLockReport`** DeviceActivityReport extension
  computes each rule's true daily total while the app is foreground and writes
  it to `UsageLedger`; display and the foreground block decision prefer that
  authoritative figure when fresh. Verify on device: the Usage counter shows
  the true total on app open (no "stalls at ~14/15m" lag); a maxed-out day
  does not re-block unused apps the next morning (or clears within one
  foreground refresh); report attribution covers category/web-domain
  selections (currently only application tokens are summed); and tune
  `RuleUsageDTO.authoritativeFreshness` (120s) so the foreground stays fresh.
- **Time-limit day-keyed enforcement** (see
  `Docs/Agents/Specs/TIME_LIMIT_DAY_KEYED_ENFORCEMENT.md`) makes each time-limit
  fire self-dating: the block and warn run on **per-day, non-repeating**
  activities (`rule-<uuid>-<dayKey>` / `tlwarn-<uuid>-<dayKey>`), armed for the
  next two scheduled days (`RuleScheduler.dayPlans` + `ScheduledDayPlanner`), and
  the monitor **drops any fire whose day key isn't today** — closing
  `TIME_LIMIT_COUNTING_HARDENING.md` §4d's Scenario B false block at the source
  rather than relying on the (still-unwired) Part B foreground reconciliation.
  Open limits keep their single repeating activity. Implemented + unit-tested;
  device-verification pending: the monitor can `startMonitoring` to self-arm the
  next day at `intervalDidEnd`; full-day capture from a midnight-armed activity;
  a real cross-midnight flush is dropped; and the per-day activity count stays
  under DeviceActivity's ~20 ceiling.
- **Schedule-rule background transitions** are now backed by DeviceActivity:
  `RuleScheduler` registers a repeating window activity per schedule rule
  (`sched-<uuid>`, plus `sched2-<uuid>` for midnight-crossing windows) and the
  monitor extension recomputes + applies/clears the shield on interval
  start/end. The foreground 30s loop remains as the reconciliation safety net
  because interval callbacks are unreliable. On-device verification of the
  background transition is still pending (the simulator does not deliver
  DeviceActivity callbacks).
- **Notifications: on-device verification pending.** The Settings →
  Notifications UI, permission flow, schedule-start scheduling, and warn-activity
  registration are unit/UI-tested, but two delivery paths are device-only: that a
  pre-scheduled `UNCalendarNotificationTrigger` actually fires ~5 min before a
  schedule window, and that the `DeviceActivityMonitor` extension can post the
  time-limit warn notification from its background process (the simulator
  delivers no DeviceActivity callbacks). Verify on device: enable both nudges;
  confirm the schedule warning arrives ~5 min before a window; confirm the
  "5 minutes left" warning arrives near a time-limit's budget; confirm toggling
  the time-limit nudge does not reset a partially-used budget (the warn lives in
  a separate `tlwarn-` activity, so the enforcement activity is never restarted).
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
