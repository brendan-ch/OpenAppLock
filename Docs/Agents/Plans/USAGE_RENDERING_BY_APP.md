# Usage rendering: per-app breakdown + time-limit-only panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the per-rule "Usage" panel time-limit-only, and for time-limit rules render a per-app usage breakdown beneath the combined total.

**Architecture:** The panel is an embedded `DeviceActivityReport` whose view is drawn by the sandboxed `OpenAppLockReport` extension. We move all shapeable logic into a pure, Shared `UsageReportFormatter` (unit-tested), have the extension scene hand it raw per-app `(name, seconds)` pairs and render the result, and gate the host's `Section("Usage")` to `rule.kind == .timeLimit`. The system view itself is device-only and untestable, so manual device validation is the final signal.

**Tech Stack:** Swift 6, SwiftUI, FamilyControls / DeviceActivity (Screen Time), Swift Testing (`@Test`/`#expect`).

**Spec:** [`Docs/Agents/Specs/USAGE_RENDERING_BY_APP.md`](../Specs/USAGE_RENDERING_BY_APP.md).

> **Post-review amendments (applied during implementation):** the code-/security-review
> pass changed three things from the task bodies below — see the spec's "Review
> outcomes" for detail. (1) `report(apps:)` sums entries by **display name** (not a
> filter+sort), so there is one row per name and `AppUsageRow.id` is unique; the
> scene emits a flat `[(name, seconds)]` and lets `report` dedup. (2) The Task 3 gate
> also requires `hasUsageSelection` (an empty selection would make the filter match
> all device activity). (3) `RuleUsageReportData` fields are `let`; per-app rows get
> `.accessibilityElement(children: .combine)`; a `reportMergesSameNameApps` test was
> added. The final code is the source of truth.

## Global Constraints

- **Build/test only via the Xcode MCP** (`BuildProject`, `RunSomeTests`, `RunAllTests`) — never raw `xcodebuild`. Get the window/tab id from `XcodeListWindows`. The scheme destination must be an iOS **Simulator** (a device destination hangs test runs).
- **Unit tests:** Swift Testing (`import Testing`, `@Test`, `#expect`). The new tests are pure (no SwiftData), so no `makeInMemoryContext()` is needed.
- **MainActor default isolation:** the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; value types crossing into the extension are marked `nonisolated` (the new formatter + types are).
- **The report system view is not unit/UI-tested** — it renders in the extension process with device-only Screen Time data, outside every mock seam, and is gated off under `-ui-testing`. Tasks 2–3 verify by **building**; behavior is validated on device by the maintainer.
- **Commits/pushes happen only when the maintainer asks** (AGENTS.md). The per-task `git commit` steps are the intended commit boundaries once they do; do not push or open a PR until asked. Every commit ends with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Doc comments are the spec** — update the owning file's `///` comment in the same commit as a behavior change.

---

### Task 1: Pure per-app usage shaping in `UsageReportFormatter`

Add the report payload types and the `report(apps:)` builder, and factor the h/m formatting into a shared `duration(minutes:)` that `todayTotal` reuses. This is the only unit-testable piece.

**Files:**
- Modify: `Shared/Platform/UsageReportFormatter.swift`
- Test: `OpenAppLockTests/UsageTests.swift` (extend the existing `UsageReportFormatterTests` suite at line 274)

**Interfaces:**
- Produces (used by Task 2 and the tests):
  - `UsageReportFormatter.duration(minutes: Int) -> String` — "1h 12m" / "45m" / "2h" / "0m" (zero)
  - `UsageReportFormatter.durationLabel(seconds: Double) -> String` — "<1m" (non-zero under a minute) / "0m" / whole-minute `duration`
  - `UsageReportFormatter.todayTotal(seconds: Double) -> String` — "1h 12m today" / "<1m today" / "No usage today" (only when truly zero)
  - `UsageReportFormatter.report(apps: [(name: String, seconds: Double)]) -> RuleUsageReportData`
  - `struct RuleUsageReportData: Equatable { var total: String; var apps: [AppUsageRow] }`
  - `struct AppUsageRow: Identifiable, Equatable { var id: String { name }; let name: String; let seconds: Double; var durationLabel: String }`

- [ ] **Step 1: Write the failing tests**

Add to the `UsageReportFormatterTests` suite in `OpenAppLockTests/UsageTests.swift` (keep the existing `formatsTotal` test):

Also update the existing `formatsTotal` test's sub-minute assertion (the
consistency change): `todayTotal(seconds: 59)` now reads `"<1m today"`, not
`"No usage today"`.

```swift
    @Test("duration renders whole hours and minutes, '0m' for zero")
    func durationStyle() {
        #expect(UsageReportFormatter.duration(minutes: 0) == "0m")
        #expect(UsageReportFormatter.duration(minutes: 45) == "45m")
        #expect(UsageReportFormatter.duration(minutes: 60) == "1h")
        #expect(UsageReportFormatter.duration(minutes: 72) == "1h 12m")
        #expect(UsageReportFormatter.duration(minutes: 125) == "2h 5m")
    }

    @Test("durationLabel reads '<1m' for non-zero sub-minute usage")
    func durationLabelStyle() {
        #expect(UsageReportFormatter.durationLabel(seconds: 0) == "0m")
        #expect(UsageReportFormatter.durationLabel(seconds: 1) == "<1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 59) == "<1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 60) == "1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 72 * 60) == "1h 12m")
    }

    @Test("a sub-minute total reads '<1m today'; zero reads 'No usage today'")
    func subMinuteTotal() {
        #expect(UsageReportFormatter.todayTotal(seconds: 0) == "No usage today")
        #expect(UsageReportFormatter.todayTotal(seconds: 40) == "<1m today")
    }

    @Test("report sums the total and lists apps heaviest-first")
    func reportSortsApps() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Mail", seconds: 5 * 60),
            (name: "Instagram", seconds: 72 * 60),
            (name: "Safari", seconds: 18 * 60),
        ])
        #expect(data.total == "1h 35m today")            // (5 + 72 + 18) = 95 min
        #expect(data.apps.map(\.name) == ["Instagram", "Safari", "Mail"])
        #expect(data.apps.map(\.durationLabel) == ["1h 12m", "18m", "5m"])
    }

    @Test("equal-usage apps are ordered by name")
    func reportTiebreak() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Reddit", seconds: 20 * 60),
            (name: "Mastodon", seconds: 20 * 60),
        ])
        #expect(data.apps.map(\.name) == ["Mastodon", "Reddit"])
    }

    @Test("a sub-minute app is kept as a '<1m' row; a zero-second app is dropped")
    func reportKeepsSubMinuteDropsZero() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Instagram", seconds: 90 * 60),
            (name: "Blip", seconds: 30),
            (name: "Ghost", seconds: 0),
        ])
        #expect(data.apps.map(\.name) == ["Instagram", "Blip"])
        #expect(data.apps.map(\.durationLabel) == ["1h 30m", "<1m"])
    }

    @Test("sub-minute apps still sum into the total")
    func reportSubMinuteAppsSumIntoTotal() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Apollo", seconds: 40),
            (name: "Bree", seconds: 40),
        ])
        #expect(data.total == "1m today")               // 80s rounds to 1 min
        #expect(data.apps.map(\.name) == ["Apollo", "Bree"])
        #expect(data.apps.map(\.durationLabel) == ["<1m", "<1m"])
    }

    @Test("report with no usage has no rows and reads 'No usage today'")
    func reportEmpty() {
        let data = UsageReportFormatter.report(apps: [])
        #expect(data.total == "No usage today")
        #expect(data.apps.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Use the Xcode MCP `RunSomeTests` for the `UsageReportFormatterTests` suite (get the window id via `XcodeListWindows`).
Expected: FAIL — compile error, `report`/`duration`/`RuleUsageReportData`/`AppUsageRow` are undefined.

- [ ] **Step 3: Write the implementation**

Replace the entire body of `Shared/Platform/UsageReportFormatter.swift` with:

```swift
//
//  UsageReportFormatter.swift
//  OpenAppLock
//

import Foundation

/// Shapes the rule-detail "Usage" report: today's combined total plus a per-app
/// breakdown. Pure and Shared so the report extension renders it and unit tests
/// cover it (the embedded `DeviceActivityReport` system view itself is
/// device-only and untestable).
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

    /// Builds the report payload from raw per-app `(name, seconds)` pairs. The
    /// total flows through `todayTotal`; rows keep every app with non-zero usage
    /// (a sub-minute app reads "<1m"), sorted by seconds descending (ties broken
    /// by name, ascending, for a stable order).
    static func report(apps: [(name: String, seconds: Double)]) -> RuleUsageReportData {
        let total = todayTotal(seconds: apps.reduce(0) { $0 + $1.seconds })
        let rows = apps
            .filter { $0.seconds > 0 }
            .sorted { lhs, rhs in
                lhs.seconds != rhs.seconds
                    ? lhs.seconds > rhs.seconds   // heaviest app first
                    : lhs.name < rhs.name         // stable tiebreak
            }
            .map { AppUsageRow(name: $0.name, seconds: $0.seconds) }
        return RuleUsageReportData(total: total, apps: rows)
    }
}

/// Today's combined usage total plus a per-app breakdown, rendered by the report
/// extension's `RuleUsageReportView`.
nonisolated struct RuleUsageReportData: Equatable {
    var total: String
    var apps: [AppUsageRow]
}

/// One app's contribution to a rule's usage today.
nonisolated struct AppUsageRow: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let seconds: Double
    var durationLabel: String { UsageReportFormatter.durationLabel(seconds: seconds) }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

`RunSomeTests` for `UsageReportFormatterTests`.
Expected: PASS — the new cases plus the existing `formatsTotal` (its outputs are unchanged by the `duration` refactor).

- [ ] **Step 5: Build the whole project to confirm the extension still compiles**

`BuildProject`. Expected: build succeeds — `OpenAppLockReport/RuleUsageReport.swift` still calls `todayTotal` (unchanged signature) at this point.

- [ ] **Step 6: Commit**

```bash
git add Shared/Platform/UsageReportFormatter.swift OpenAppLockTests/UsageTests.swift
git commit -m "feat: shape per-app usage report data in UsageReportFormatter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Render the per-app breakdown in the report extension

Switch the report scene from a single `String` total to the `RuleUsageReportData` payload, collect per-app durations from the DeviceActivity results, and add a dedicated view that draws the total plus one row per app.

**Files:**
- Modify: `OpenAppLockReport/RuleUsageReport.swift`
- Create: `OpenAppLockReport/RuleUsageReportView.swift`

**Interfaces:**
- Consumes (from Task 1): `RuleUsageReportData`, `AppUsageRow`, `UsageReportFormatter.report(apps:)`.
- Produces: `RuleUsageReportView(data: RuleUsageReportData)` (the scene's `Content`).

- [ ] **Step 1: Replace the report scene**

Replace the entire body of `OpenAppLockReport/RuleUsageReport.swift` with:

```swift
//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Renders the filtered rule's usage for today — a combined total plus a per-app
/// breakdown. The host (`RuleDetailSheet`, time-limit rules only) scopes the data
/// via the report's filter, so this scene stays identity-agnostic and never reads
/// the app group. Runs only while the host foregrounds a
/// `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (RuleUsageReportData) -> RuleUsageReportView = { RuleUsageReportView(data: $0) }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> RuleUsageReportData {
        // Sum each app's foreground duration, keyed so the same app across
        // segments/categories accumulates into one row.
        var byKey: [String: (name: String, seconds: Double)] = [:]
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName
                        ?? app.application.bundleIdentifier
                        ?? "Unknown"
                    let key = app.application.bundleIdentifier ?? name
                    byKey[key, default: (name, 0)].seconds += app.totalActivityDuration
                }
            }
        }
        return UsageReportFormatter.report(apps: byKey.values.map { ($0.name, $0.seconds) })
    }
}
```

> If the build fails on `app.application.localizedDisplayName` / `.bundleIdentifier`, consult the DeviceActivity SDK via `mcp__xcode__DocumentationSearch` for the correct accessor on `DeviceActivityData`'s application activity — only the two property reads change; the fallback chain and surrounding shape stay the same.

- [ ] **Step 2: Create the renderer view**

Create `OpenAppLockReport/RuleUsageReportView.swift`:

```swift
//
//  RuleUsageReportView.swift
//  OpenAppLockReport
//

import SwiftUI

/// The rule-detail "Usage" panel's contents, drawn inside the report extension:
/// today's total, then one row per app — "name … flexible gap … duration",
/// heaviest-first. The flexible `Spacer` lets the gap grow and shrink with the
/// row width; the name truncates so it never pushes the duration off-screen, and
/// the durations are monospaced so they line up as a column. Just the total line
/// when there are no per-app rows (no usage, or every app under a minute).
struct RuleUsageReportView: View {
    let data: RuleUsageReportData

    var body: some View {
        if data.apps.isEmpty {
            Text(data.total)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(data.total)
                    .font(.subheadline.weight(.semibold))
                ForEach(data.apps) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(app.durationLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

`BuildProject`. Expected: build succeeds (both the app and the `OpenAppLockReport` extension target). There is no unit test — the scene runs only in the extension process against device-only data.

- [ ] **Step 4: Commit**

```bash
git add OpenAppLockReport/RuleUsageReport.swift OpenAppLockReport/RuleUsageReportView.swift
git commit -m "feat: render per-app usage breakdown in the report extension

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Limit the usage panel to time-limit rules

Gate the host's `Section("Usage")` to `rule.kind == .timeLimit` (removing it for schedule and open-limit rules), and update the superseded decisions in the prior spec.

**Files:**
- Modify: `OpenAppLock/Views/Rules/RuleDetailSheet.swift` (the `Section("Usage")` gate + its doc comment)
- Modify: `Docs/Agents/Specs/ACTIVE_RULES_AND_USAGE_REPORT.md` (Decisions log)

**Interfaces:** none new — uses existing `rule.kind` / `RuleKind.timeLimit`.

- [ ] **Step 1: Update the gate and its comment**

In `OpenAppLock/Views/Rules/RuleDetailSheet.swift`, replace the comment + `if` block that wraps the usage `Section`:

Replace:

```swift
            // Live Screen Time usage for this rule's apps, rendered inside the
            // report extension (the only place the data is available). Gated
            // under UI testing — the system view does not run in the harness —
            // and blank when there is no usage.
            if !LaunchConfiguration.current.isUITesting {
                Section("Usage") {
```

with:

```swift
            // Live Screen Time usage for this rule's apps, rendered inside the
            // report extension (the only place the data is available). Time-limit
            // rules only: schedule rules have no usage budget, and open-limit
            // rules are governed by opens (not foreground duration), so the panel
            // would mislead there. Gated under UI testing — the system view does
            // not run in the harness — and blank when there is no usage.
            if rule.kind == .timeLimit && !LaunchConfiguration.current.isUITesting {
                Section("Usage") {
```

(The `Section("Usage")` body, `usageFilter`, and identifiers are unchanged.)

- [ ] **Step 2: Update the superseded decisions in the prior spec**

In `Docs/Agents/Specs/ACTIVE_RULES_AND_USAGE_REPORT.md`, in the `## Decisions log`:

Replace:

```markdown
- v1 report content: **total usage today**, per-rule filter.
```
with:
```markdown
- v1 report content: **total usage today**, per-rule filter. *(Superseded by
  [`USAGE_RENDERING_BY_APP.md`](USAGE_RENDERING_BY_APP.md): time-limit rules now
  also render a per-app breakdown beneath the total.)*
```

Replace:

```markdown
- Report shown for **all rule kinds**.
```
with:
```markdown
- Report shown for **all rule kinds**. *(Superseded: now **time-limit-only** —
  schedule and open-limit detail sheets no longer show the panel. See
  [`USAGE_RENDERING_BY_APP.md`](USAGE_RENDERING_BY_APP.md).)*
```

- [ ] **Step 3: Build, then run the affected suites**

`BuildProject`, then `RunSomeTests` for `UsageReportFormatterTests` (and, if convenient, the `UsageUITests` class). Expected: build succeeds; tests pass. No UI test references the panel (it is gated off under `-ui-testing`), so none needs changing — `UsageUITests` asserts only the Active Rules rows and that a row opens `detailRuleName`.

- [ ] **Step 4: Commit**

```bash
git add OpenAppLock/Views/Rules/RuleDetailSheet.swift Docs/Agents/Specs/ACTIVE_RULES_AND_USAGE_REPORT.md
git commit -m "feat: show the usage panel only for time-limit rules

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Full suite + device-validation handoff

- [ ] **Step 1: Run the full unit suite**

`RunAllTests` (Simulator destination). Expected: all green (the only logic change is the `UsageReportFormatter` refactor, covered by Task 1; everything else is view/extension code).

- [ ] **Step 2: Hand device validation to the maintainer**

The embedded `DeviceActivityReport` renders nothing on the Simulator, so report the per-spec on-device checklist back to the maintainer rather than claiming it verified:
- A time-limit rule's detail shows the "Usage" section: a total line, then one row per app with ≥1 min today, heaviest-first; the name→duration gap fills the row width; long names truncate without hiding the duration.
- A schedule rule's detail and an open-limit rule's detail show **no** "Usage" section.
- A time-limit rule with no usage today shows "No usage today".

## Self-review notes

- **Spec coverage:** per-app rows (Task 1 + 2), h/m style shared with the total (Task 1), flexible-spacing row layout (Task 2), schedule + open-limit panel removal via time-limit gate (Task 3), no-icons / raw-total non-goals respected, prior-spec supersede (Task 3), device validation handoff (Task 4). All covered.
- **Type consistency:** `RuleUsageReportData` / `AppUsageRow` / `report(apps:)` / `duration(minutes:)` names match across Tasks 1–2; the scene's `Content` is `RuleUsageReportView`.
- **Build ordering:** Task 1 keeps `todayTotal`'s signature so the extension compiles before Task 2 rewrites the scene.
