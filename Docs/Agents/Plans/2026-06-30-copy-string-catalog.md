# Copy → String Catalog Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Project note:** the flow-gate clamp requires an allowed flow to be active before editing code — this migration maps to `spec-driven-development`; ensure it (or an equivalent gate-unlocking flow) is invoked before the first code edit.

**Goal:** Move every user-facing string into one String Catalog keyed by symbolic identifiers, so all copy and typography (’ “ ” …) live outside the code.

**Architecture:** A single `Shared/Localizable.xcstrings` (default table), auto-embedded in all five product targets via the `Shared/` synchronized group, is the sole home for prose. A `nonisolated enum CopyKey` is the typed index of every key; call sites use `Text(.someKey)` (SwiftUI) or `CopyKey.someKey.string` (plain-String producers). Two guardrail tests (completeness + typography) make the silent-fallback risk of symbolic keys safe.

**Tech Stack:** Swift 6 / SwiftUI / SwiftData, Xcode String Catalogs (`.xcstrings`), `LocalizedStringResource` / `String(localized:)`, Swift Testing. Build & test through the **Xcode MCP** tools only.

## Global Constraints

- iOS 26 target; Swift 6; project default actor isolation is **MainActor** — `CopyKey` is used from nonisolated extension code (shields, monitor), so it MUST be declared `nonisolated`.
- One catalog only: `Shared/Localizable.xcstrings`, default `Localizable` table, `sourceLanguage: "en"`. Every entry uses `"extractionState": "manual"` (keys are symbolic, not code-extracted).
- Keys are symbolic, dotted, `feature.element` camelCase. **No prose or typographic characters appear in code** — only in catalog values.
- Typography: apostrophes/closing single quotes → `’` (U+2019), double quotes → `“ ”` (U+201C/U+201D), ellipsis → `…` (U+2026). Interpolation lives in catalog values as `%lld` / `%@`.
- Ship `en` only. No new languages, no pluralization overhaul (existing count/plural branching stays in code; the catalog holds phrase templates).
- **Do not** route accessibility identifiers (`newRuleButton`, `ruleCard-<name>`, …) or `Diag`/`os.Logger` message strings through the catalog.
- Build/test via Xcode MCP (`BuildProject`, `RunSomeTests`, `RunAllTests`); scheme destination must be an iOS **simulator**. Catalog entries authored by editing the `.xcstrings` JSON directly (single `en` locale, symbolic keys); the MCP `StringCatalog*` tools target the translate-to-locale workflow and are not used here.
- Conventional commits; every commit ends with a `Co-Authored-By:` trailer naming the agent/model. Work on branch `feat/copy-string-catalog`; open a PR at the end (do not push to `main`).

---

### Task 1: Infrastructure + walking skeleton

Create the catalog, the `CopyKey` accessor, the SwiftUI convenience init, and the two guardrail tests; prove the whole pipeline by migrating two real call sites end-to-end.

**Files:**
- Create: `Shared/Localizable.xcstrings`
- Create: `Shared/Copy/CopyKey.swift`
- Create: `Shared/Copy/Text+CopyKey.swift`
- Create: `OpenAppLockTests/CopyCatalogTests.swift`
- Modify: `OpenAppLock/Views/Onboarding/OnboardingView.swift` (the `"Requesting…"` call site)
- Modify: `OpenAppLock/Views/Rules/RuleEditorView.swift:215` (the `can't`/`it's` footer)
- Modify: `AGENTS.md` (add a Rules-feature-map row)

**Interfaces:**
- Produces:
  - `nonisolated enum CopyKey: String, CaseIterable`
  - `var resource: LocalizedStringResource` — for SwiftUI / resource-taking APIs
  - `var string: String` — resolved value, for plain-String producers
  - `func string(_ args: CVarArg...) -> String` — resolved + `String(format:)` for interpolation
  - `extension Text { init(_ key: CopyKey) }` — enables `Text(.key)`

- [ ] **Step 1: Write the failing guardrail tests**

Create `OpenAppLockTests/CopyCatalogTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenAppLock

struct CopyCatalogTests {
    // Every key must resolve to a real catalog value, not fall back to its raw key.
    @Test func everyKeyResolvesToACatalogValue() {
        for key in CopyKey.allCases {
            let resolved = key.string
            #expect(resolved \!= key.rawValue, "Missing catalog entry for key '\(key.rawValue)'")
            #expect(\!resolved.isEmpty, "Empty catalog value for key '\(key.rawValue)'")
        }
    }

    // No resolved copy may contain dumb typography.
    @Test func everyValueUsesSmartTypography() {
        for key in CopyKey.allCases {
            let v = key.string
            #expect(\!v.contains("'"), "Straight apostrophe in '\(key.rawValue)': \(v)")
            #expect(\!v.contains("\""), "Straight double quote in '\(key.rawValue)': \(v)")
            #expect(\!v.contains("..."), "Literal three-dot ellipsis in '\(key.rawValue)': \(v)")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Use Xcode MCP `RunSomeTests` for `OpenAppLockTests/CopyCatalogTests`.
Expected: FAIL to compile — `CopyKey` is undefined.

- [ ] **Step 3: Create the `CopyKey` accessor**

Create `Shared/Copy/CopyKey.swift`:

```swift
import Foundation

/// The single index of every user-facing string in the app. The prose and all
/// typography live in `Shared/Localizable.xcstrings`, keyed by these raw values;
/// code only ever references the symbolic case. `nonisolated` so shield/monitor
/// extension code (outside the MainActor default) can resolve copy.
nonisolated enum CopyKey: String, CaseIterable {
    // Walking-skeleton seeds (more added per surface in later tasks):
    case onboardingRequesting = "onboarding.requesting"
    case ruleEditorCantPauseWhileActive = "ruleEditor.cantPauseWhileActive"

    /// Localized resource — default `Localizable` table, `.main` bundle (the
    /// catalog is embedded in every target, so `.main` resolves per process).
    var resource: LocalizedStringResource { LocalizedStringResource(String.LocalizationValue(rawValue)) }

    /// Resolved String for non-SwiftUI producers (shields, notifications, logic).
    var string: String { String(localized: resource) }

    /// Resolved + formatted for interpolated copy (placeholders live in the catalog value).
    func string(_ args: CVarArg...) -> String { String(format: string, arguments: args) }
}
```

- [ ] **Step 4: Create the SwiftUI convenience init**

Create `Shared/Copy/Text+CopyKey.swift` (kept separate so the core enum needs no SwiftUI import):

```swift
import SwiftUI

extension Text {
    /// `Text(.onboardingRequesting)` — compile-checked copy at SwiftUI call sites.
    init(_ key: CopyKey) { self.init(key.resource) }
}
```

- [ ] **Step 5: Create the catalog with the two seed entries**

Create `Shared/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "onboarding.requesting" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Requesting…" } }
      }
    },
    "ruleEditor.cantPauseWhileActive" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "This block can’t be paused while it’s active." } }
      }
    }
  },
  "version" : "1.0"
}
```

Add all subsequent entries by editing this `.xcstrings` JSON directly (append to the `strings` object, same shape: `"extractionState": "manual"` plus an `en` `stringUnit` value with correct typography).

- [ ] **Step 6: Run the guardrail tests to verify they pass**

Use Xcode MCP `RunSomeTests` for `OpenAppLockTests/CopyCatalogTests`.
Expected: PASS (both seed keys resolve to smart-typography values).

- [ ] **Step 7: Swap the two seed call sites**

In `OpenAppLock/Views/Rules/RuleEditorView.swift`, the `hardModeSection` footer:

```swift
// before
Text("This block can't be paused while it's active.")
// after
Text(.ruleEditorCantPauseWhileActive)
```

In `OpenAppLock/Views/Onboarding/OnboardingView.swift`, the requesting label:

```swift
// before
isRequesting ? "Requesting…" : "Allow Screen Time Access",
// after — Allow-Screen-Time is migrated in Task 5; use its resolved string here for now
isRequesting ? CopyKey.onboardingRequesting.string : "Allow Screen Time Access",
```

(The `pillButton` helper takes a `String`; leave `"Allow Screen Time Access"` untouched until Task 5 adds its key.)

- [ ] **Step 8: Add the AGENTS.md feature-map row**

In `AGENTS.md`, under "Where each topic is documented", add:

```
| User-facing copy (String Catalog, symbolic keys) | `Shared/Copy/CopyKey.swift`, `Shared/Localizable.xcstrings`; design spec `Docs/Agents/Specs/COPY_STRING_CATALOG_MIGRATION.md` |
```

- [ ] **Step 9: Build, run tests, commit**

Xcode MCP `BuildProject` (simulator destination) → expect success.
Xcode MCP `RunSomeTests` for `OpenAppLockTests/CopyCatalogTests` → expect PASS.

```bash
git checkout -b feat/copy-string-catalog
git add Shared/Copy Shared/Localizable.xcstrings OpenAppLockTests/CopyCatalogTests.swift \
        OpenAppLock/Views/Rules/RuleEditorView.swift OpenAppLock/Views/Onboarding/OnboardingView.swift AGENTS.md
git commit -m "feat: add String Catalog + CopyKey scaffold with guardrail tests

Co-Authored-By: <agent/model> <email>"
```

---

### The per-surface migration recipe (Tasks 2–7)

Each surface task applies the same mechanical recipe. It is spelled out here once and referenced by each task; the completeness guardrail (Task 1) is the coverage proof.

For each user-facing literal in the task's file list:
1. Choose a `feature.element` key (see the prefix list in the spec §2).
2. Add the entry to `Shared/Localizable.xcstrings` by editing the JSON directly, with the **typographically-correct** value (`’ “ ” …`; interpolation as `%lld`/`%@`) and `"extractionState": "manual"`.
3. Add the matching `case` to `CopyKey`.
4. Swap the call site:
   - SwiftUI text APIs → `Text(.key)`; where the API takes `LocalizedStringResource` (e.g. `.navigationTitle`, `Button`, `Section`, `Toggle`, `Label`), pass `CopyKey.key.resource`; if a specific overload won't compile, use the `Text`-closure form, e.g. `Button(action: …) { Text(.key) }`.
   - Plain-String producers → `CopyKey.key.string` (or `.string(args…)`).
5. **Do not** touch `.accessibilityIdentifier(...)` strings, `systemImage:` names, or log strings.

Completion gate for every surface task: `CopyCatalogTests` green, `BuildProject` green, any updated exact-string assertions green.

---

### Task 2: Migrate the Rules views

**Files (Modify):**
- `OpenAppLock/Views/Rules/RuleEditorView.swift` (~18; `cantPause` done in Task 1)
- `OpenAppLock/Views/Rules/RuleDetailSheet.swift` (~13)
- `OpenAppLock/Views/Rules/RulesListView.swift` (~5)
- `OpenAppLock/Views/Rules/NewRuleSheet.swift` (~4)
- Test: `OpenAppLockUITests/*` assertions that hard-code any of the above strings

**Interfaces:** Consumes `CopyKey`, `Text(.key)` from Task 1. Produces `ruleEditor.*`, `ruleDetail.*`, `rulesList.*`, `newRule.*` keys.

- [ ] **Step 1: Update UI-test assertions that will change (RED)**

Grep the UI suite for the literals you are about to migrate; update any exact-string expectation to the smart-typography value. Example (illustrative — apply to real matches):

```swift
// before
app.staticTexts["This block can't be paused while it's active."]
// after
app.staticTexts["This block can’t be paused while it’s active."]
```

Run the affected UI test → expect FAIL (code still emits dumb text where not yet migrated).

- [ ] **Step 2: Apply the recipe to each file**

Worked example — a `Section` header + `Toggle` in `RuleEditorView`:

```swift
// before
Section("Schedule") { … }
Toggle("Hard Mode", isOn: $draft.hardMode).accessibilityIdentifier("hardModeToggle")
// after  (identifier untouched)
Section(CopyKey.ruleEditorScheduleSection.resource) { … }
Toggle(CopyKey.ruleEditorHardModeToggle.resource, isOn: $draft.hardMode).accessibilityIdentifier("hardModeToggle")
```

Catalog entries added for each (e.g. `"ruleEditor.scheduleSection" → "Schedule"`, `"ruleEditor.hardModeToggle" → "Hard Mode"`).

- [ ] **Step 3: Build**

Xcode MCP `BuildProject` → expect success.

- [ ] **Step 4: Run guardrails + affected tests (GREEN)**

`RunSomeTests` for `OpenAppLockTests/CopyCatalogTests` and the touched UI flows → expect PASS.

- [ ] **Step 5: Commit**

```bash
git add Shared/Localizable.xcstrings Shared/Copy/CopyKey.swift OpenAppLock/Views/Rules OpenAppLockUITests
git commit -m "feat: migrate Rules views copy to String Catalog

Co-Authored-By: <agent/model> <email>"
```

---

### Task 3: Migrate the Settings views

**Files (Modify):**
- `OpenAppLock/Views/Settings/SettingsView.swift` (~11)
- `OpenAppLock/Views/Settings/NotificationSettingsView.swift` (~8; already uses curly quotes — carry them into the values verbatim)
- `OpenAppLock/Views/Settings/DiagnosticLogsView.swift` (~9; this is the **Settings → Diagnostics UI**, which is user-facing copy — in scope. The `Diag`/logger message strings elsewhere are not.)
- Test: any UI assertion on Settings/Notifications/Diagnostics strings (e.g. `NotificationSettingsUITests`)

**Interfaces:** Produces `settings.*`, `notifications.*`, `diagnostics.*` keys.

- [ ] **Step 1: Update affected UI-test assertions (RED)** — same pattern as Task 2 Step 1.
- [ ] **Step 2: Apply the recipe** to each file. Multi-line footer example from `NotificationSettingsView`:

```swift
// before
"“Schedule starting soon” warns 5 minutes before a schedule rule blocks. "
    + "“Time limit almost up” warns when a time limit has 5 minutes left."
// after
Text(.notificationsFooter)
// catalog "notifications.footer" → "“Schedule starting soon” warns 5 minutes before a schedule rule blocks. “Time limit almost up” warns when a time limit has 5 minutes left."
```

- [ ] **Step 3: Build** (`BuildProject`) → success.
- [ ] **Step 4: Run guardrails + affected tests** → PASS.
- [ ] **Step 5: Commit** (`feat: migrate Settings views copy to String Catalog`).

---

### Task 4: Migrate the App Lists views

**Files (Modify):**
- `OpenAppLock/Views/AppLists/AppListEditorView.swift` (~10)
- `OpenAppLock/Views/AppLists/AppListLibraryView.swift` (~11)
- `OpenAppLock/Views/AppLists/AppListDetailView.swift` (~2)
- `OpenAppLock/Views/AppLists/ManageAppListsView.swift` (~1)
- Test: any UI assertion on App Lists strings

**Interfaces:** Produces `appLists.*` keys.

- [ ] **Step 1: Update affected UI-test assertions (RED).** Includes `"Your edits to this list haven't been saved."` → `"…haven’t been saved."`
- [ ] **Step 2: Apply the recipe** to each file.
- [ ] **Step 3: Build** → success.
- [ ] **Step 4: Run guardrails + affected tests** → PASS.
- [ ] **Step 5: Commit** (`feat: migrate App Lists views copy to String Catalog`).

---

### Task 5: Migrate Home, Onboarding, shell & components

**Files (Modify):**
- `OpenAppLock/Views/Home/HomeView.swift` (~4)
- `OpenAppLock/Views/Onboarding/OnboardingView.swift` (~6; `Requesting…` done in Task 1 — finish `"Allow Screen Time Access"`, `"Continue"`, bullets, declined message)
- `OpenAppLock/Views/MainSidebarView.swift` (~1) and `OpenAppLock/Views/Navigation/AppSection.swift` (section display labels, if user-visible)
- `OpenAppLock/Views/Components/DayOfWeekPicker.swift` (~1)
- Test: `OpenAppLockUITests` onboarding/home assertions

**Interfaces:** Produces `home.*`, `onboarding.*`, `nav.*`, `dayPicker.*` keys.

- [ ] **Step 1: Update affected UI-test assertions (RED).**
- [ ] **Step 2: Apply the recipe.** Finish the Task 1 onboarding call site:

```swift
// after (both keys now exist)
isRequesting ? CopyKey.onboardingRequesting.string : CopyKey.onboardingAllowScreenTime.string,
```

- [ ] **Step 3: Build** → success.
- [ ] **Step 4: Run guardrails + affected tests** → PASS.
- [ ] **Step 5: Commit** (`feat: migrate Home/Onboarding/shell copy to String Catalog`).

---

### Task 6: Migrate the logic-layer producers

The composed/interpolated copy. Keep `String` return types; swap literals to `CopyKey`. This task carries the bulk of the **unit-test** churn (RuleStatus/UsageDisplay tests assert exact labels).

**Files (Modify):**
- `OpenAppLock/Logic/RuleStatus.swift` (`label`, `countdown`, `rowContext`)
- `OpenAppLock/Logic/UsageDisplay.swift` (`budgetPhrase`, `homeSubtitle`)
- Shared display strings feeding these, if user-facing: `Shared/Models/RuleKind.swift` (`displayName`), `Shared/Models/Weekday.swift`, `OpenAppLock/Models/RulePreset.swift` (preset/category names)
- Test: `OpenAppLockTests/RuleStatusTests*.swift`, `OpenAppLockTests/UsageDisplayTests*.swift` (update expected strings to smart typography)

**Interfaces:** Produces `status.*`, `usage.*`, `ruleKind.*`, `weekday.*`, `preset.*` keys.

- [ ] **Step 1: Update the unit-test expectations (RED)**

```swift
// RuleStatusTests — before
#expect(status.label(relativeTo: now) == "No days selected")
// after (unchanged text here, but any string with typography updates, e.g. apostrophes)
```
Change every expected literal that gains typography. Run `RunSomeTests` for the logic suites → expect FAIL where code still emits old text.

- [ ] **Step 2: Migrate simple + composed cases**

```swift
// RuleStatus.label — before
case .disabled: "Disabled"
case .active(let until): "\(Self.countdown(from: now, to: until)) left"
// after
case .disabled: CopyKey.statusDisabled.string
case .active(let until): CopyKey.statusActiveLeft.string(Self.countdown(from: now, to: until))
// catalog "status.disabled" → "Disabled";  "status.activeLeft" → "%@ left"
```

```swift
// RuleStatus.rowContext — before
return "Blocked until tomorrow"
// after
return CopyKey.statusBlockedUntilTomorrow.string
```

- [ ] **Step 3: Migrate interpolated allowance phrases**

```swift
// UsageDisplay.budgetPhrase — before
case .timeLimit: "\(snapshot.dailyLimitMinutes)m / day"
case .openLimit: "\(snapshot.maxOpens) opens / day"
// after
case .timeLimit: CopyKey.usageMinutesPerDay.string(snapshot.dailyLimitMinutes)
case .openLimit: CopyKey.usageOpensPerDay.string(snapshot.maxOpens)
// catalog "usage.minutesPerDay" → "%lldm / day";  "usage.opensPerDay" → "%lld opens / day"
```

The `homeSubtitle` separator becomes a key too: `"usage.subtitleSeparator" → "%@ · %@"`, called `CopyKey.usageSubtitleSeparator.string(kind.displayName, rowContext)`.

- [ ] **Step 4: Build** (`BuildProject`) → success.
- [ ] **Step 5: Run logic suites + guardrails (GREEN)** → PASS.
- [ ] **Step 6: Commit** (`feat: migrate logic-layer copy to String Catalog`).

---

### Task 7: Migrate enforcement & extension copy

Shield and notification strings — the copy rendered from nonisolated extension processes. Exercises the `nonisolated` `CopyKey` and cross-target bundle resolution.

**Files (Modify):**
- `Shared/Enforcement/ShieldPresentation.swift` (title/subtitle/button, incl. interpolation)
- `OpenAppLockShieldConfig/ShieldConfigurationExtension.swift` (consumes `ShieldPresentation`; verify no residual literals)
- `OpenAppLockMonitor/LimitWarningNotifier.swift` (notification `title`/`body`)
- `OpenAppLockReport/RuleUsageReport.swift`, `Shared/Platform/UsageReportFormatter.swift` (report labels)
- Test: `OpenAppLockTests/ShieldPresentationTests*.swift`

**Interfaces:** Produces `shield.*`, `notification.*`, `usageReport.*` keys.

- [ ] **Step 1: Update `ShieldPresentation` unit-test expectations (RED).**

- [ ] **Step 2: Migrate the static + interpolated + plural-branch cases**

```swift
// ShieldPresentation — before
static let blockedTitle = "App Blocked"
subtitle: "No opens left today — the block lifts tomorrow.",
subtitle: "Opened \(opensUsed) of \(maxOpens) times today. "
    + "Each open lasts \(sessionMinutes) minutes.",
secondaryButton: remaining == 1 ? "Open (1 left)" : "Open (\(remaining) left)"
// after
static let blockedTitle = CopyKey.shieldBlockedTitle.string
subtitle: CopyKey.shieldNoOpensLeft.string,
subtitle: CopyKey.shieldOpenLimitSubtitle.string(opensUsed, maxOpens, sessionMinutes),
secondaryButton: remaining == 1
    ? CopyKey.shieldOpenButtonOne.string
    : CopyKey.shieldOpenButtonMany.string(remaining)
```

Catalog values: `"shield.blockedTitle" → "App Blocked"`; `"shield.noOpensLeft" → "No opens left today — the block lifts tomorrow."`; `"shield.openLimit.subtitle" → "Opened %lld of %lld times today. Each open lasts %lld minutes."`; `"shield.openButtonOne" → "Open (1 left)"`; `"shield.openButtonMany" → "Open (%lld left)"`. The `remaining == 1` branch (plural logic) stays in code per the Global Constraints.

- [ ] **Step 3: Build all targets** (`BuildProject`) → success. Confirm the extension targets compile against `nonisolated CopyKey`.

- [ ] **Step 4: Run `ShieldPresentation` suite + guardrails (GREEN)** → PASS.

- [ ] **Step 5: Verify catalog is embedded in the extensions**

After a build, confirm each `.appex` bundle contains the compiled strings (e.g. inspect `BUILT_PRODUCTS_DIR/OpenAppLockShieldConfig.appex/Localizable.strings` or `.lproj`). If missing, confirm the `.xcstrings` is in the target's *Copy Bundle Resources* (it should be automatic via the `Shared/` synchronized group).

- [ ] **Step 6: Commit** (`feat: migrate shield/notification copy to String Catalog`).

---

### Task 8: Completeness sweep + finalize

**Files:** none new; verification + PR.

- [ ] **Step 1: Straggler sweep**

Grep for remaining user-facing literals the per-surface tasks may have missed:

```bash
grep -rnE '(Text|Label|Button|Section|Toggle|Stepper|Menu|Link|\.navigationTitle|\.alert|\.confirmationDialog)\(\s*"[A-Za-z]' --include="*.swift" OpenAppLock/Views
grep -rnE '"[A-Z][a-z].{6,}"' --include="*.swift" OpenAppLock/Logic Shared/Enforcement OpenAppLock*Monitor OpenAppLock*Shield* OpenAppLock*Report \
  | grep -vE 'accessibilityIdentifier|systemImage|Logger|Diag|forKey|identifier|subsystem|category'
```

For each true hit, apply the recipe. Re-run until only non-copy strings (identifiers, symbol names, log messages) remain; note anything intentionally left.

- [ ] **Step 2: Full suite**

Xcode MCP `RunAllTests` → expect PASS (unit + UI, iPhone and iPad matrix). Re-run any known flaky suites in isolation before treating a failure as a regression.

- [ ] **Step 3: Manual UI validation**

`RunProject` on a simulator; visually confirm representative screens (a rule editor footer, the shield-less flows, Settings → Notifications footer, onboarding) render smart quotes/ellipsis and no raw keys. If the simulator/MCP is unavailable, say so and hand verification to the user.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/copy-string-catalog
gh pr create --title "feat: migrate user-facing copy to a String Catalog" --body "…summary + test plan + Claude Code footer…"
```

Include the "Generated with Claude Code" footer per project convention. Do not merge — the maintainer reviews.

---

## Self-Review

**Spec coverage:** Catalog (§1) → Task 1. Key convention (§2) → recipe + all tasks. Accessor (§3) → Task 1. Consumption per surface (§4): Views → Tasks 2–5; logic → Task 6; extensions/interpolation → Task 7. Testing & guardrails (§5) → Task 1 (guards) + per-task assertion updates + Task 8 (full suite). Migration order (§mechanics) → Task ordering. Out-of-scope (identifiers, plurals, logs, languages) → Global Constraints + Task 7 plural-branch note + Task 8 sweep excludes. Risks (§) → silent fallback (Task 1 guard), extension bundle (Task 7 Step 5), test churn (per-task RED steps). No gaps found.

**Placeholder scan:** `<agent/model> <email>` in commit trailers is a deliberate fill-in (agent identity is per-executor). Worked examples are labeled illustrative where the exact literal set is discovered during migration; every code *pattern* (simple, composed, interpolated, plural-branch, static) has concrete before/after. No TBD/TODO left.

**Type consistency:** `CopyKey` API (`resource` / `string` / `string(_:)`) and `Text(_:CopyKey)` are defined in Task 1 and used verbatim in Tasks 2–7. Key raw values in worked examples match their `case` names.
