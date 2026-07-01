# Copy → String Catalog Migration — Design Spec

Status: **design** (not yet implemented) · Proposed branch: `feat/copy-string-catalog`

Agent-managed (lives under `Docs/Agents/`). Once implemented, the behavior source
of truth is the doc comment on `Shared/Copy/CopyKey.swift` plus the catalog
itself; this spec is the design rationale. Add a "Rules feature map" row in
`AGENTS.md` pointing at `CopyKey.swift` when the work lands.

## Goal

Decouple all user-facing copy from source code so that typography — smart quotes
(’ “ ”) and the ellipsis (…) — and the prose itself live in **one place
outside the code**: a String Catalog. Code references stable symbolic keys and
never contains prose or typographic characters.

Two problems motivate this:

1. **Typographic inconsistency.** Copy is currently inline string literals and is
   mid-transition: contractions use dumb apostrophes
   (`"This block can't be paused while it's active."` —
   `OpenAppLock/Views/Rules/RuleEditorView.swift`), while other strings already
   use correct Unicode (`"Requesting…"` — `OpenAppLock/Views/Onboarding/OnboardingView.swift`;
   curly quotes in `OpenAppLock/Views/Settings/NotificationSettingsView.swift`).
2. **Coupling.** Copy is scattered across SwiftUI Views and plain-`String`
   producers in the logic/enforcement layer, with no single home to reason about
   wording or typography.

Ship English (`en`) only. The catalog structure makes additional languages
possible later, but no other language is in scope.

## Current state (as of this spec)

- No String Catalog (`.xcstrings`), no `.strings` files, zero uses of
  `String(localized:)` / `LocalizedStringResource` / `NSLocalizedString`.
  Project is `developmentRegion = en`, `knownRegions = (en, Base)`.
- Copy lives in two forms:
  - **SwiftUI view literals** — `Text("…")`, `Label("…")`, `.navigationTitle`,
    etc. (~102 occurrences in `OpenAppLock/Views`). These are already
    `LocalizedStringKey`.
  - **Plain `String` producers** — `RuleStatus.label/countdown/rowContext`
    (`OpenAppLock/Logic/RuleStatus.swift`), `UsageDisplay.budgetPhrase`
    (`OpenAppLock/Logic/UsageDisplay.swift`), `ShieldPresentation.title/subtitle`
    (`Shared/Enforcement/ShieldPresentation.swift`), and extension copy
    (shield config, `OpenAppLockMonitor/LimitWarningNotifier.swift` notification
    `title`/`body`). ~57 literals across logic + extensions. Shields
    (`.init(text: presentation.title, …)`) and notifications
    (`notification.title = content.title`) require `String`.

Deduped, this is on the order of **~120–150 distinct strings** — a tractable
single migration.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Copy home | Modern **String Catalog** (`.xcstrings`) | Apple-native, Xcode-editable, localization-ready |
| Key style | **Symbolic** dotted keys (`ruleEditor.cantPauseWhileActive`) | Maximum decoupling; code holds zero prose/typography |
| Scope | **Everything, one migration** | Views + logic producers + extensions in a single pass |
| Catalog layout | **One file** `Shared/Copy.xcstrings`, own `Copy` table | Single "separate place"; auto-embedded in every target; own table isolates it from auto-extraction |
| Accessor | **Typed `CopyKey` enum** | Compile-checked; symbolic keys otherwise fail silently |

## Architecture

### 1. The catalog

One file: `Shared/Copy.xcstrings`, its **own `Copy` table** (deliberately NOT the default `Localizable` table — see auto-extraction note below).

The `Shared/` folder is a `PBXFileSystemSynchronizedRootGroup` that is a member
of **all five product targets** (app, `OpenAppLockMonitor`,
`OpenAppLockShieldConfig`, `OpenAppLockShieldAction`, `OpenAppLockReport` —
verified in `OpenAppLock.xcodeproj/project.pbxproj`). A `.xcstrings` file placed
there is auto-assigned to each target's *Copy Bundle Resources* phase from a
single source file, so each process's `Bundle.main` resolves it. This is why one
catalog reaches the extensions without content duplication and without promoting
`Shared/` to a framework.

All typography (’ “ ” …) and all format placeholders (`%lld`, `%@`) live in the
catalog **values** only.

**Auto-extraction isolation.** The product targets build with `SWIFT_EMIT_LOC_STRINGS`
set to `NO`, and the catalog uses a non-default `Copy` table. Xcode's build-time
string extraction only writes literal `Text("…")` strings into the default
`Localizable` table, so our hand-authored `Copy` table is never polluted with
raw-text-keyed stubs. (Discovered during Task 1: with the default table + 
`SWIFT_EMIT_LOC_STRINGS = YES`, a build stub-inserted ~97 literal keys.)

### 2. Key convention

Symbolic, dotted, `feature.element` with a camelCase tail:

```
"ruleEditor.cantPauseWhileActive"  → en: "This block can’t be paused while it’s active."
"onboarding.requesting"            → en: "Requesting…"
"shield.blocked.title"             → en: "App Blocked"
"shield.openLimit.subtitle"        → en: "Opened %lld of %lld times today."
```

Feature prefixes track the screen/domain that owns the string (`home.`, `rules.`,
`ruleEditor.`, `ruleDetail.`, `settings.`, `appLists.`, `onboarding.`,
`notifications.`, `shield.`, `usage.`, `status.`).

### 3. The typed accessor

`Shared/Copy/CopyKey.swift` — the single index of every string:

```swift
enum CopyKey: String, CaseIterable {
    case ruleEditorCantPauseWhileActive = "ruleEditor.cantPauseWhileActive"
    case onboardingRequesting           = "onboarding.requesting"
    case shieldBlockedTitle             = "shield.blocked.title"
    case shieldOpenLimitSubtitle        = "shield.openLimit.subtitle"
    // …one case per string

    /// Localized resource (default `Localizable` table, `.main` bundle).
    var resource: LocalizedStringResource { .init(String.LocalizationValue(rawValue)) }
    /// Resolved String, for non-SwiftUI producers (shields, notifications, logic).
    var string: String { String(localized: resource) }
    /// Resolved + formatted, for interpolated copy (placeholders in the catalog).
    func string(_ args: CVarArg...) -> String { String(format: string, arguments: args) }
}

extension Text {
    /// `Text(.onboardingRequesting)` — compile-checked, leading-dot call site.
    init(_ key: CopyKey) { self.init(key.resource) }
}
```

Default table + default bundle mean no `table:`/`bundle:` arguments at any call
site.

### 4. Consumption per surface

- **SwiftUI Views** → `Text(.ruleEditorCantPauseWhileActive)`, `Label(...)`, etc.
- **Logic producers** (`RuleStatus`, `UsageDisplay`) → keep returning `String`;
  body becomes `CopyKey.x.string`. Signatures unchanged, so callers don't churn.
- **Extensions** (shield config, notifications; require `String`) →
  `CopyKey.shieldBlockedTitle.string`.
- **Interpolation** → `CopyKey.shieldOpenLimitSubtitle.string(opensUsed, maxOpens)`
  against a `%lld … %lld` value. Existing plural/number logic stays in code (see
  Out of scope); the catalog holds only the phrase template.

### 5. Testing & guardrails

Symbolic keys fail *silently* (a missing entry renders the raw key), so two
mechanical guards are load-bearing:

1. **Completeness test** — iterate `CopyKey.allCases`; assert each `.string`
   resolves to something **other than its own `rawValue`** and is non-empty.
   Catches any key with no catalog entry.
2. **Typography test** — iterate `CopyKey.allCases`; assert no resolved value
   contains a straight `'`, a straight `"`, or a literal `...`. This enforces the
   "think in smart quotes" invariant and blocks catalog regressions.

Existing exact-string assertions migrate in lockstep: `RuleStatus` label unit
tests and the UI tests that assert exact header/row strings (`detailRow-<label>`,
section headers rendered with `.textCase(nil)`) are updated to the
smart-typography values. This is the primary source of test churn.

## Migration mechanics & order (single PR)

1. Add empty `Shared/Copy.xcstrings`, `Shared/Copy/CopyKey.swift`
   (enum + `Text` init), and the two guardrail tests.
2. Migrate surface by surface — **Views → logic producers → extensions** —
   moving each literal into the catalog with corrected typography and swapping the
   call site to a `CopyKey`.
3. Update the exact-string test assertions as each surface is converted.
4. Run the full unit + UI suite; manually validate the UI on the simulator.
5. Branch `feat/copy-string-catalog`, open a PR for the maintainer.

Catalog entries are authored by editing the `.xcstrings` JSON directly (single `en`
source value per symbolic key). The Xcode MCP `StringCatalog*` tools target the
translate-to-locale workflow and are not used.

## Out of scope (YAGNI)

- **Additional languages.** Structure is localization-ready; only `en` ships.
- **Pluralization overhaul.** Existing plural/count logic (e.g. countdown labels,
  usage phrases) stays in code; the catalog holds phrase templates only.
- **Accessibility identifiers** (`newRuleButton`, `ruleCard-<name>`, …) — not
  user-facing copy; untouched. These must remain stable per the UI-test harness.
- **Log / diagnostic strings** — developer-facing (`Diag`, `os.Logger`);
  untouched.

## Risks / gotchas

- **Silent key fallback** — mitigated by the completeness test (§5.1).
- **Bundle resolution in extensions** — relies on the catalog being embedded in
  every target via the `Shared/` synchronized group; verify each `.appex` bundle
  actually contains the compiled strings after the first build.
- **Test churn** — exact-string assertions must move with the copy or the suite
  goes red mid-migration; convert assertions surface-by-surface.
- **Accessibility identifiers vs labels** — do not route identifiers through the
  catalog; only visible copy.
