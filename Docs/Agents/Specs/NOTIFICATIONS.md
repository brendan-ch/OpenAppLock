# Notifications — Design Spec

Status: **reviewed (adversarial pass incorporated)** · Branch: `feat/notifications`

## Goal

Add opt-in local notifications. Entry point is a new **Notifications** sub-page
in Settings where the user can:

1. **Grant notification permission** (system authorization prompt + status).
2. **Toggle two notification types** independently:
   - **Schedule starting soon** — fires ~5 min before a Schedule rule's window
     begins.
   - **Time limit almost up** — fires when a Time-Limit rule has ~5 min of daily
     allowance left.

Both types are off by default and inert unless notification permission is
granted. Open-limit rules are out of scope (no time-based "almost up" moment).
24-hour (`start == end`) schedule rules are out of scope for "starting soon"
(a perpetual window never meaningfully "starts").

## Why two delivery mechanisms

| Type | Trigger | Mechanism |
|---|---|---|
| Schedule starting soon | Wall-clock, known in advance | Pre-scheduled repeating `UNCalendarNotificationTrigger` (collapsed per rule), recomputed when rules change |
| Time limit almost up | Usage-driven, not predictable | A **dedicated DeviceActivity warn activity** per opted-in time-limit rule, with one threshold event at `budget − 5` min; the monitor extension posts the notification when it fires |

A schedule window's start is a recurring calendar moment, so iOS owns delivery
natively. A time limit's "5 minutes left" depends on future usage, so it must be
event-driven off Screen Time's usage counter.

## Single authorization gate

A derived bool `AppGroup.notificationsAuthorizedKey` is the one source of truth
for "notifications can actually be delivered". `NotificationAuthorization` writes
it on every `refresh()`/`request()`. **Every effective gate is `authorized &&
typeToggle`** so that revoking permission in system Settings (picked up on the
next auth refresh) tears down both mechanisms. The two raw type toggles are
stored separately so they survive a permission round-trip.

## Architecture

### A. Notification authorization — `OpenAppLock/Services/NotificationAuthorization.swift` (app target)

Mirrors `ScreenTimeAuthorization` (protocol + real + mock + `@Observable`
wrapper), but async because `UNUserNotificationCenter` is async.

```
enum NotificationAuthorizationStatus { case notDetermined, denied, authorized }

protocol NotificationAuthorizationProviding: Sendable {
    func currentStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization() async -> NotificationAuthorizationStatus
}
struct UserNotificationAuthorizationProvider: NotificationAuthorizationProviding { … }  // UNUserNotificationCenter.current()
final class MockNotificationAuthorizationProvider: NotificationAuthorizationProviding { … }  // seeded status, optional grant-fails

@MainActor @Observable final class NotificationAuthorization {
    private(set) var status: NotificationAuthorizationStatus
    func refresh() async      // also writes notificationsAuthorizedKey
    func request() async      // also writes notificationsAuthorizedKey
}
```

Status mapping: `.authorized / .provisional / .ephemeral` → `.authorized`;
`.denied` → `.denied`; `.notDetermined` → `.notDetermined`. Request options
`[.alert, .sound]`. Injected via environment from `OpenAppLockApp`; mock provider
under `-ui-testing`, seeded from a launch arg so both the *grant* transition and
the *already-granted* state are UI-testable.

### B. Persisted state — `Shared/AppGroup.swift` + `OpenAppLock/Services/AppSettings.swift` + `Shared/NotificationPreferences.swift`

New app-group keys:
```
AppGroup.notifyScheduleStartKey    = "notifyScheduleStartEnabled"   // raw toggle
AppGroup.notifyTimeLimitEndingKey  = "notifyTimeLimitEndingEnabled" // raw toggle
AppGroup.notificationsAuthorizedKey = "notificationsAuthorized"     // derived auth mirror
```

`AppSettingsStore` gains two `@Observable` Bool props (default false, `didSet`
persists; `resetForTesting` clears all three keys).

`Shared/NotificationPreferences.swift` — a value type read by **both** app and
the monitor extension (pure; no `UserNotifications` import, so safe in `Shared/`
which compiles into all targets):
```
struct NotificationPreferences {
    let defaults: UserDefaults            // injected; default AppGroup.defaults
    var scheduleStartEnabled: Bool { authorized && rawScheduleStart }   // effective
    var timeLimitEndingEnabled: Bool { authorized && rawTimeLimitEnding } // effective
}
```

### C. Settings UI

- `SettingsView`: new `Section` with `NavigationLink` → `NotificationSettingsView()`,
  `Label("Notifications", systemImage: "bell.badge")`, id `notificationSettingsButton`.
- `OpenAppLock/Views/Settings/NotificationSettingsView.swift` (new):
  - **Permission section** from `NotificationAuthorization.status`:
    - `.notDetermined` → "Allow Notifications" button (`allowNotificationsButton`)
      → `await authorization.request()`.
    - `.denied` → footer + "Open Settings" button (`openNotificationSettingsButton`)
      → `UIApplication.openSettingsURLString`.
    - `.authorized` → "Notifications allowed" row (`notificationStatusLabel`).
  - **Types section** — two toggles, **disabled** unless `.authorized`:
    - "Schedule starting soon" (`scheduleStartNotificationToggle`) →
      `settings.notifyScheduleStartEnabled`.
    - "Time limit almost up" (`timeLimitNotificationToggle`) →
      `settings.notifyTimeLimitEndingEnabled`.
  - Toggling either, or returning from a grant, calls `enforcer.refresh(rules:)`
    so both mechanisms re-sync immediately.
  - `.task { await authorization.refresh() }` to pick up system-Settings changes
    (and surface a revocation).

### D. Schedule-start scheduling (app-only)

Pure planning, isolated from `UNUserNotificationCenter`.

- `OpenAppLock/Services/ScheduleStartNotificationPlan.swift` (app target — only
  the app schedules these; keeps dead code out of the 4 extensions):
  ```
  struct PlannedNotification: Equatable, Sendable {
      let identifier: String   // NotificationIDs.scheduleStart(ruleID:, weekday:|daily)
      let dateComponents: DateComponents   // weekday?+hour+minute, repeats weekly (or daily when collapsed)
      let title: String
      let body: String
  }
  enum ScheduleStartNotificationPlan {
      static let leadMinutes = 5
      static func requests(for snapshots: [RuleSnapshot], leadMinutes: Int = leadMinutes) -> [PlannedNotification]
  }
  ```
  Per rule included only when: `kind == .schedule`, `isEnabled`, non-empty days,
  **`selectionData != nil`** (don't warn for a schedule that blocks nothing), and
  **not 24h** (`startMinutes != endMinutes`). For each enabled weekday `d` with
  start `S`:
  - `notify = S − leadMinutes`
  - `notify ≥ 0` → fire weekday `d` at minute `notify`
  - `notify < 0`  → fire **previous** weekday `prev = d == 1 ? 7 : d-1` at minute
    `notify + 1440` (lead crosses back over midnight; e.g. start 00:02 Mon →
    23:57 Sun). Only the window *start* matters, so midnight-crossing windows are
    handled by this alone.
  - **Collapse:** when the resulting fire-day set is all 7 weekdays at the same
    minute, emit ONE daily `DateComponents(hour:minute:)` (no weekday) → 1 request
    instead of 7. (`Weekday.everyDay`; the every-day case is common and the 64
    pending-request cap is real.) Otherwise one weekly request per fire weekday.
  - Title `"Heads up"`, body `"\(name) starts in 5 minutes."`

- `OpenAppLock/Services/NotificationScheduler.swift` (app target):
  ```
  protocol LocalNotificationScheduling: Sendable {
      func pendingScheduleStartIdentifiers() async -> [String]
      func replaceScheduleStart(remove: [String], add: [PlannedNotification]) async
  }
  struct UserNotificationScheduler: LocalNotificationScheduling { … }   // UNUserNotificationCenter, weekly/daily repeating triggers
  final class MockNotificationScheduler: LocalNotificationScheduling { … }

  actor NotificationScheduler {            // actor → overlapping syncs serialize
      init(center: LocalNotificationScheduling, defaults: UserDefaults = AppGroup.defaults)
      func sync(snapshots: [RuleSnapshot], enabled: Bool) async
  }
  ```
  `sync`: desired = `enabled ? plan.requests(...) : []`, capped deterministically
  at 60 (sorted by weekday/minute/identifier; log dropped count). Diff against
  pending `schedule-start-*` identifiers: remove stale, add missing. A
  **fingerprint** (hash of `enabled` + `leadMinutes` + each schedule rule's
  id/name/start/end/days/hasApps), stored in the injected `defaults`,
  short-circuits the no-op case so the 30 s loop doesn't churn. Pause is
  deliberately **excluded** from the fingerprint: a soft unblock only applies to
  an already-active window whose start has passed, so it never collides with a
  "starting soon" notification.

  Driven from `RuleEnforcer.refresh` via an injected optional `NotificationScheduler`
  (nil under `-ui-testing`). refresh is sync, so the call is
  `Task { await scheduler.sync(...) }`; the actor serializes and the fingerprint
  dedups, so overlapping 30 s ticks are safe.

### E. Time-limit warn — a dedicated, conditional warn activity

**Key correctness decision:** the warn threshold lives in its OWN DeviceActivity
activity (`tlwarn-<uuid>`), never on the enforcement (`rule-<uuid>`) activity.
This means turning the time-limit nudge on/off only ever starts/stops the *warn*
activity — the block activity, and its threshold accounting, is **never restarted**.
That fully avoids resetting users' time-limit usage mid-day (which an extra event
on the shared block activity would force via the fingerprint/restart path) and
preserves the time-limit-counting-hardening work.

- `Shared/MonitoringPlan.swift` additions:
  ```
  private static let warnActivityPrefix = "tlwarn-"
  private static let warnEventPrefix    = "warn-"
  static let limitWarningLeadMinutes = 5
  static func warnActivityName(for ruleID: UUID) -> String         // "tlwarn-<uuid>"
  static func ruleID(fromWarnActivityName: String) -> UUID?
  static func warnEvent(forLimit: Int) -> [String: Int]?           // nil when limit ≤ lead; else ["warn-<L-5>": L-5]
  ```
  `ruleID(fromDailyActivityName:)` still matches only `rule-` (not `tlwarn-`),
  so no collision. `blockEvent`/`minutes(fromEventName:)` are untouched.

- `RuleScheduler.sync` (time-limit branch): in addition to the existing block
  activity, register the warn activity **iff**
  `NotificationPreferences(defaults:).timeLimitEndingEnabled && warnEvent != nil`.
  Separate fingerprint (`"tlwarn|<limit>|<selection>"`); add its name to
  `desiredNames`; extend the stale-cleanup filter to recognise
  `ruleID(fromWarnActivityName:)`. When the toggle is off (or auth lost, since the
  effective gate ANDs auth) the warn activity is absent from `desiredNames` →
  stopped on the next sync. The block activity's desiredNames/fingerprint are
  unchanged → never restarted by this feature.

- `DeviceActivityMonitorExtension.eventDidReachThreshold` — explicit control flow
  so the warn branch precedes the `minutes-` parse (the old guard would have
  dropped warn events):
  ```
  if let ruleID = MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) {
      LimitWarningNotifier().notifyIfEligible(ruleID: ruleID)
      return
  }
  guard let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue),
        let minutes = MonitoringPlan.minutes(fromEventName: event.rawValue) else { return }
  enforcement.handleUsageMinutes(minutes, ruleID: ruleID)
  uninstallProtection.reconcile()
  ```
  (The warn activity's `intervalDidStart` matches no handler prefix → harmless no-op.)

- Decision logic split for testability:
  - `Shared/LimitWarningDecision.swift` (pure; Shared, no UserNotifications import):
    ```
    enum LimitWarningDecision {
        static func content(for snapshot: RuleSnapshot?, preferences: NotificationPreferences,
                            now: Date, calendar: Calendar) -> (title: String, body: String)?
    }
    ```
    Non-nil only when: `preferences.timeLimitEndingEnabled`, snapshot exists, is an
    enabled `.timeLimit`, not paused, scheduled today, and **not already at/over
    limit** (a late/stale warn after the block shouldn't nag). Body:
    `"\(name): 5 minutes of your time limit left."`
  - `OpenAppLockMonitor/LimitWarningNotifier.swift` (**monitor target, not Shared**
    — it imports `UserNotifications`; keep that out of the Shield/Report
    extensions): thin shell that builds the snapshot/ledger, calls
    `LimitWarningDecision.content`, and on non-nil posts via
    `UNUserNotificationCenter.current().add` with an immediate (nil) trigger.

## Target membership (corrected from review)

`Shared/` compiles into ALL five targets. So:
- Shared (pure, cross-target): `NotificationPreferences`, `ScheduleStartNotificationPlan`?→**no, app-only**, `LimitWarningDecision`, `NotificationIDs`, `MonitoringPlan` additions.
- App-only (`OpenAppLock/`): `NotificationAuthorization`, `NotificationScheduler`,
  `ScheduleStartNotificationPlan`, `NotificationSettingsView`, `AppSettings` edits.
- Monitor-only (`OpenAppLockMonitor/`): `LimitWarningNotifier` (imports UserNotifications).

`NotificationIDs` (build/parse of `schedule-start-…` identifiers) is app-only
too (only the app schedules them); placed alongside `NotificationScheduler`.

## Files

New (app): `Services/NotificationAuthorization.swift`,
`Services/NotificationScheduler.swift` (incl. `NotificationIDs`, `PlannedNotification`,
mock), `Services/ScheduleStartNotificationPlan.swift`,
`Views/Settings/NotificationSettingsView.swift`.
New (Shared): `NotificationPreferences.swift`, `LimitWarningDecision.swift`.
New (Monitor): `LimitWarningNotifier.swift`.
New tests: `NotificationAuthorizationTests`, `AppSettingsNotificationTests`,
`ScheduleStartNotificationPlanTests`, `NotificationSchedulerTests`,
`MonitoringPlanWarnTests`, `RuleSchedulerWarnTests`, `LimitWarningDecisionTests`,
UI `NotificationSettingsUITests`.

Edited: `Shared/AppGroup.swift`, `OpenAppLock/Services/AppSettings.swift`,
`Shared/MonitoringPlan.swift`, `OpenAppLock/Services/RuleScheduler.swift`,
`OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`,
`OpenAppLock/Services/RuleEnforcer.swift`,
`OpenAppLock/Views/Settings/SettingsView.swift`,
`OpenAppLock/OpenAppLockApp.swift`, `AGENTS.md` (drop "notification nudges" from
out-of-scope; add a feature-map row + this spec link).

## TDD plan (red → green per unit)

1. `MonitoringPlanWarnTests` — `warnActivityName`/decode round-trip; `tlwarn-`
   not decoded as `rule-`; `warnEvent` nil for budget ≤ 5, `["warn-<L-5>": L-5]`
   for L > 5.
2. `ScheduleStartNotificationPlanTests` — normal weekday; `S < leadMinutes`
   previous-day rollover; Sunday→Saturday wrap; multi-day; every-day collapse to a
   single daily request; disabled/empty-days/no-apps/24h/non-schedule excluded.
3. `AppSettingsNotificationTests` — defaults false; persist; reset clears.
4. `NotificationAuthorizationTests` — wrapper maps provider status; request
   updates status + writes the authorized mirror; denied path.
5. `NotificationSchedulerTests` (mock center, `freshDefaults()`) — enabled adds
   desired; disabled removes ours; fingerprint no-ops on repeat; rule change
   re-syncs; cap truncation deterministic.
6. `RuleSchedulerWarnTests` (`MockActivityMonitor`, injected defaults) —
   time-limit registers the warn activity only when the effective gate is on and
   budget > 5; block activity is registered regardless and is NOT restarted when
   the warn toggle flips.
7. `LimitWarningDecisionTests` — content when eligible; nil for disabled toggle /
   unauthorized / paused / not-scheduled-today / at-or-over limit / open-limit /
   schedule.

UI: `NotificationSettingsUITests` — Settings → Notifications; assert the *grant*
transition (launch `.notDetermined` → tap Allow → toggles enable) and that both
toggles flip + persist (coordinate tap per the SwiftUI-Toggle gotcha).

## Residual risks (device-only; cannot validate on simulator)

- **Posting from the monitor extension.** Whether a `DeviceActivityMonitor`
  extension may post a `UNUserNotificationCenter` notification is verified only on
  device (the simulator delivers no DeviceActivity callbacks). Isolated behind
  `LimitWarningNotifier`. Joins the existing "on-device verification pending" gaps.
- **Sub-budget threshold reliability.** One warn threshold ≈ the block threshold
  we already depend on; best-effort nudge, documented as such.
- **Activity cap.** An opted-in time-limit rule uses 2 daily activities
  (block + warn). Block is registered first; warn start is best-effort (failures
  swallowed by the existing `start()` wrapper). Documented.
- **DST.** `UNCalendarNotificationTrigger` recomputes per occurrence in the user's
  timezone; a notify time inside the spring-forward gap is skipped, fall-back may
  double. Best-effort, accepted.
- **Revocation while app closed.** The derived authorized-mirror is only refreshed
  when the app runs; a stale `true` is harmless because the extension's `add`
  silently no-ops without real authorization, and registrations are torn down on
  the next foreground refresh.
```
