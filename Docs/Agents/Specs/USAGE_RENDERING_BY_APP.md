# Usage rendering: per-app breakdown, time-limit-only panel

Status: **Designed** (2026-06-28) — not yet implemented. Supersedes two decisions
in [`ACTIVE_RULES_AND_USAGE_REPORT.md`](ACTIVE_RULES_AND_USAGE_REPORT.md) (see
"Supersedes" below). On-device validation of the report rendering is the only
real signal — the Simulator cannot exercise a `DeviceActivityReport`.

## Motivation

PR #29 added a per-rule "Usage" panel to `RuleDetailSheet`: an embedded
`DeviceActivityReport` that renders one line of today's combined foreground usage
("1h 12m today"). It is shown for **all three rule kinds** and shows only a
single total. Three problems:

1. **Time-limit rules** want to know *which* app is eating the budget, not just a
   combined total — a per-app breakdown.
2. **Schedule rules** have no usage budget; a foreground-duration total is noise
   on a schedule's detail.
3. **Open-limit rules** are governed by *opens*, not duration. The duration total
   doesn't reflect the metric the rule enforces, so it is misleading. Opens are
   already tracked reliably in `RuleUsageDTO.opensUsed` (written by the
   shield-action extension, which — unlike the sandboxed report extension — *can*
   write to the app group) and already surface elsewhere.

## Goals

- **Time limit:** the panel renders a per-app usage breakdown *in addition to* the
  combined total — one row per app, "`<app name>`  …flexible gap…  `1h 12m`".
- **Schedule:** the usage panel is removed for schedule rules.
- **Open limit:** the usage panel is removed for open-limit rules.

Net effect: the per-rule "Usage" panel is **time-limit-only**, and for time
limits it shows total + per-app rows.

## Non-goals

- App icons. An app's icon/name is not reliably obtainable from an
  `ApplicationToken` outside `FamilyActivityPicker`; v1 renders the app's
  `localizedDisplayName` as plain text (falling back to bundle id, then
  "Unknown"). Icons can be revisited later.
- Framing the total against the rule's budget ("X of 45m"). `totalActivityDuration`
  includes Home-Screen/idle time per Apple's docs and can over-read; the budget is
  also *combined* across the rule's apps. The total stays a raw "today" figure, as
  in PR #29.
- UI-testing the report screen. It is a system view rendered by the extension
  process, outside every mock seam, with no Screen Time data in the Simulator. It
  stays gated off under `-ui-testing` (unchanged).
- Any change to enforcement, the Active Rules home section, or the open-limit
  opens-tracking path.

## Design

### 1. `RuleDetailSheet.swift` — a full-page usage link, time-limit-only

The report is reached via a `NavigationLink` that pushes a **full page**, not
embedded in the detail `List`. A `DeviceActivityReport` renders out-of-process and
never reports its content height back to the host, so in a `List`/`Form` row it
clips at whatever fixed frame it is given (no amount of `minHeight` auto-grows it);
a full page gives it the whole screen. The link is gated to time-limit rules with
a non-empty selection (and off under UI testing):

```swift
if rule.kind == .timeLimit && hasUsageSelection
    && !LaunchConfiguration.current.isUITesting {
    Section {
        NavigationLink {
            RuleUsageReportPage(filter: usageFilter)
        } label: {
            Label("Today's Usage", systemImage: "chart.bar")
        }
        .accessibilityIdentifier("usageReportLink")
    }
}
```

The pushed page hosts the report at full size:

```swift
private struct RuleUsageReportPage: View {
    let filter: DeviceActivityFilter
    var body: some View {
        DeviceActivityReport(.ruleUsage, filter: filter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("ruleUsageReport")
    }
}
```

The link is shown for time-limit rules only (schedules have no usage budget; open
limits are governed by opens, not foreground duration). The `hasUsageSelection`
guard (from the security review) hides it when the rule selects no
apps/categories/web domains — an empty `DeviceActivityFilter` matches *all* device
activity, which the per-app breakdown would otherwise enumerate:

```swift
private var hasUsageSelection: Bool {
    let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
    return !selection.applicationTokens.isEmpty
        || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty
}
```

The `usageFilter` computed property is unchanged.

### 2. Pure shaping + types — `Shared/Platform/UsageReportFormatter.swift`

The per-app shaping is pure and lives in `Shared/` so the report extension renders
it and unit tests cover it. Add the configuration types and a `report(apps:)`
builder; keep `todayTotal(seconds:)`.

```swift
/// What the rule-usage report renders: today's combined total plus a per-app
/// breakdown. Built by `UsageReportFormatter.report(apps:)` so the (untestable)
/// async DeviceActivity iteration stays thin and the shaping is unit-tested.
nonisolated struct RuleUsageReportData: Equatable {
    let total: String          // "1h 12m today" / "<1m today" / "No usage today"
    let apps: [AppUsageRow]    // one per display name; zero-second names dropped
}

nonisolated struct AppUsageRow: Identifiable, Equatable {
    var id: String { name }    // unique: `report` sums entries that share a name
    let name: String
    let seconds: Double         // raw foreground seconds; source for label + sort
    var durationLabel: String { UsageReportFormatter.durationLabel(seconds: seconds) }  // "1h 12m" / "45m" / "<1m"
}

nonisolated enum UsageReportFormatter {
    /// "1h 12m" / "45m" / "2h" / "0m" — whole hours and minutes, omitting a zero
    /// part but rendering "0m" for zero.
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(remainder)m"
    }

    /// A single usage figure from raw seconds: "<1m" for any non-zero usage under
    /// a minute, otherwise the whole-minute `duration`; "0m" for none. Shared by
    /// the per-app rows and `todayTotal` so both read the same way.
    static func durationLabel(seconds: Double) -> String {
        guard seconds > 0 else { return "0m" }
        if seconds < 60 { return "<1m" }
        return duration(minutes: Int(seconds / 60))
    }

    /// The total line: "1h 12m today" / "<1m today"; "No usage today" only when
    /// there is no usage at all.
    static func todayTotal(seconds: Double) -> String {
        guard seconds > 0 else { return "No usage today" }
        return "\(durationLabel(seconds: seconds)) today"
    }

    /// Builds the report payload from raw per-app `(name, seconds)` pairs. Entries
    /// sharing a display name are summed into one row (the same app across activity
    /// segments, and two apps the user can't tell apart), which also keeps
    /// `AppUsageRow.id` (the name) unique. The total flows through `todayTotal`;
    /// rows keep every name with non-zero usage (a sub-minute one reads "<1m"),
    /// sorted by seconds descending (ties broken by name, ascending).
    static func report(apps: [(name: String, seconds: Double)]) -> RuleUsageReportData {
        var secondsByName: [String: Double] = [:]
        for app in apps {
            secondsByName[app.name, default: 0] += app.seconds
        }
        let total = todayTotal(seconds: secondsByName.values.reduce(0, +))
        let rows = secondsByName
            .filter { $0.value > 0 }
            .map { AppUsageRow(name: $0.key, seconds: $0.value) }
            .sorted { lhs, rhs in
                lhs.seconds != rhs.seconds
                    ? lhs.seconds > rhs.seconds   // heaviest app first
                    : lhs.name < rhs.name         // stable tiebreak
            }
        return RuleUsageReportData(total: total, apps: rows)
    }
}
```

The per-app rows and the total both flow through `durationLabel(seconds:)`, so
they read consistently — a sub-minute app and a sub-minute total both say "<1m".

### 3. Report extension renderer — `OpenAppLockReport/RuleUsageReport.swift`

Change the scene's `Configuration` from `String` to `RuleUsageReportData`. The
async `makeConfiguration` emits one `(name, seconds)` per app activity and hands
them to `UsageReportFormatter.report(apps:)`, which sums entries sharing a display
name (the dedup lives in `report`, not here). `content` renders a small dedicated
view.

```swift
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (RuleUsageReportData) -> RuleUsageReportView = { RuleUsageReportView(data: $0) }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> RuleUsageReportData {
        var apps: [(name: String, seconds: Double)] = []
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName
                        ?? app.application.bundleIdentifier
                        ?? "Unknown"
                    apps.append((name, app.totalActivityDuration))
                }
            }
        }
        return UsageReportFormatter.report(apps: apps)
    }
}
```

The exact app-name accessor (`app.application.localizedDisplayName`) is confirmed
at build time against the DeviceActivity SDK; if the property differs, the
fallback chain (bundle id → "Unknown") and the surrounding shape are unchanged.

### 4. Renderer view — `OpenAppLockReport/RuleUsageReportView.swift` (new)

A focused SwiftUI view in the extension target, drawn full-page (the report is
pushed, not embedded — §1). The total is a header; each app is a row whose `HStack`
uses a flexible `Spacer`, so the gap between name and duration tracks the width.
The name truncates so it never pushes the duration off-screen; the durations are
monospaced so they line up as a column. A `ScrollView` so a rule with many apps
scrolls rather than clipping (the `DeviceActivityReport` can't report its content
height to the host).

```swift
struct RuleUsageReportView: View {
    let data: RuleUsageReportData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(data.total)                          // header; "No usage today" when empty
                    .font(.title3.weight(.semibold))
                ForEach(data.apps) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)              // flexible gap
                        Text(app.durationLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)   // VoiceOver: "name, duration"
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
```

### 5. Tests — `OpenAppLockTests/UsageTests.swift`

Extend the existing `UsageReportFormatterTests` suite (the `todayTotal` cases stay)
with `report(apps:)` cases:

- Empty input → total "No usage today", no rows.
- Total flows through `todayTotal` (apps summing to 72 min → "1h 12m today"); a
  sub-minute total reads "<1m today".
- Per-app rows sorted by seconds descending; ties ordered by name.
- A sub-minute app is kept as a "<1m" row; a zero-second app is dropped.
- Entries sharing a display name merge into one row (keeps `id` unique).
- `duration(minutes:)` renders the h/m style ("45m", "1h 12m", "2h", "0m" for 0);
  `durationLabel(seconds:)` adds the "<1m" / "0m" cases.

The renderer view and the embedded `DeviceActivityReport` are not unit/UI-tested
(system view, device-only data); manual device validation is the signal.

### 6. Docs

- Update the doc comments on `RuleDetailSheet.swift`,
  `OpenAppLockReport/RuleUsageReport.swift`, and `UsageReportFormatter.swift` in
  the same commit as the behavior change (per AGENTS.md).
- Update [`ACTIVE_RULES_AND_USAGE_REPORT.md`](ACTIVE_RULES_AND_USAGE_REPORT.md)
  per "Supersedes" below.
- No change to the "Rules feature map" rows in AGENTS.md (the owning files are the
  same).

## Supersedes

Two decisions in `ACTIVE_RULES_AND_USAGE_REPORT.md` change; update its Decisions
log / Design §4 to point here:

- "v1 report content: **total usage today**, per-rule filter." → time-limit
  rules now also render a **per-app breakdown** beneath the total.
- "Report shown for **all rule kinds**." → the panel is **time-limit-only**;
  schedule and open-limit detail sheets no longer show it.

## Manual device validation (handed to maintainer)

The Simulator renders no `DeviceActivityReport` data, so verify on device:

- A time-limit rule's detail shows a **"Today's Usage"** row; tapping it pushes a
  full "Usage" page with a total header and one row per app that has ≥1 min today,
  sorted heaviest-first; the gap between name and duration fills the row width;
  long app names truncate without pushing the duration off-screen; a rule with
  many apps scrolls rather than clipping.
- A schedule rule's detail and an open-limit rule's detail show **no** usage link.
- A time-limit rule with no usage today shows "No usage today" on the page.
- A time-limit rule with *no apps selected* shows **no** usage link (the
  empty-selection guard) rather than every app on the device.

## Review outcomes

Adversarial code + security review (pre-merge). Accepted and applied:

- **Row-identity collision (code review):** two distinct apps sharing a display
  name produced duplicate `ForEach` ids (a dropped row). `report` now sums by
  display name, so there is one row per name and `id` is unique.
- **Empty-selection over-disclosure (security review):** an empty selection makes
  `DeviceActivityFilter` match all device activity; the per-app breakdown would
  enumerate every app. Added the `hasUsageSelection` guard so the panel is hidden
  without a selection.
- Minor: `RuleUsageReportData` fields are `let`; per-app rows get
  `.accessibilityElement(children: .combine)` for VoiceOver.

Deferred (with reasoning — not in this change):

- **Bidi/control-character sanitizing of app names:** a naive strip of
  `.control` + `.format` Unicode scalars would break legitimate emoji ZWJ
  sequences (U+200D is `.format`); `.lineLimit(1)` already caps overflow. A
  surgical bidi-only stripper can be added later if name-spoofing becomes a
  concern.
- **Web-domain usage is not counted** (the scene sums `category.applications`
  only): pre-existing behavior from the prior combined-total report, out of scope
  here. Noted in `ACTIVE_RULES_AND_USAGE_REPORT.md`'s risks.

## File-by-file change summary

| File | Change |
|---|---|
| `OpenAppLock/Views/Rules/RuleDetailSheet.swift` | `NavigationLink` ("Today's Usage") → full-page `RuleUsageReportPage`, gated to `rule.kind == .timeLimit` + `hasUsageSelection`; report on a page (not a List row) so it doesn't clip |
| `Shared/Platform/UsageReportFormatter.swift` | Add `RuleUsageReportData` / `AppUsageRow` + `duration`/`durationLabel`/`report`; refactor `todayTotal` |
| `OpenAppLockReport/RuleUsageReport.swift` | Scene `Configuration` → `RuleUsageReportData`; emit per-app `(name, seconds)` |
| `OpenAppLockReport/RuleUsageReportView.swift` | New: total + per-app rows with flexible spacing |
| `OpenAppLockTests/UsageTests.swift` | Expand `UsageReportFormatterTests` (duration/durationLabel/report cases) |
| `Docs/Agents/Specs/ACTIVE_RULES_AND_USAGE_REPORT.md` | Update two superseded decisions to point here |
