# MULTI_APP_LIST_RULES

Status: implemented (V3 schema). Summary of the feature + its self-review.

## Spec

A rule may select **multiple app lists**. Enforcement treats the union of all
selected lists' app/category/web-domain tokens as **one combined app list** and
applies the pre-existing logic unchanged. The UI is the previous UI with
multi-select: in the rule editor's app-list picker each row tap **toggles**
that list into the rule's selection; leaving is the back button. Labels: one
selected list keeps the old "name · N Apps" summary; several lists show
"N Lists · M Apps" (M = summed per-list counts, may double-count overlap — the
enforced union dedupes real tokens on device).

## Design

- **Schema V3** (`OpenAppLock/Models/V3/`): `BlockingRule.appLists: [AppList]`
  to-many relationship; `AppList.rules` inverse re-pointed at `appLists`
  (`.nullify`). The V2 `appList` column is kept as the migration data source
  only — after promotion it is always nil and app code never touches it.
- **Migration** (`OpenAppLockSchemaMigrationPlan.migrateV2toV3`):
  structural part is the automatic additive lightweight migration;
  `didMigrate` (`MigrationHelpers.promoteV2RuleAppLists`) copies each rule's
  legacy `appList` into `appLists`, then strips the legacy column. Fetch/save
  throw: a failed one-shot migration replays on next launch instead of
  silently dropping selections. Tested on-disk in
  `MultiAppListMigrationTests` (fresh temp store per test).
- **Union**: `BlockingRule.combinedSelectionData` (in
  `BlockingRule+DTO.swift`) merges every selected list's
  `FamilyActivitySelection` and feeds `RuleSnapshotDTO.selectionData`, so all
  enforcement paths (shields, shield-lookup arbitration, DeviceActivity
  events, report filter) read the union without extension changes. With ≤ 1
  data-carrying list the original bytes pass through unchanged (byte-identical
  to pre-V3 for all existing rules).
- **Draft**: `RuleDraft.appLists: [AppList]` (sorted per
  `BlockingRule.sortedAppLists`); `apply` compares **sets** of IDs (order is
  not a user-visible attribute) and assigns only on change.
- **UI**: `AppListLibraryView` picker mode toggles membership (creating a list
  appends it); `RuleEditorForm`'s row shows "Choose" / "name · N Apps" /
  "N Lists · M Apps" (`ruleEditor.appListMultipleSummaryFormat`);
  `RuleDetailSheet` shows the same via `BlockingRule.appListSummary`;
  `MainView`'s rule-change token fingerprints app-list IDs + summed counts.

## TDD record

- Red: `MultiAppListMigrationTests` (compile failure → then failing),
  `MultiAppListRuleTests` + `ProjectedAppListLabelTests`.
- Green: focused suites → full `OpenAppLockTests` (386 tests) — all pass.
- On-simulator verification (UI-test harness, seeded): picker shows both
  seeded lists, both toggled selected simultaneously, editor row shows
  "2 Lists · 5 Apps", committed rule's detail shows the same.

## Self-review (code-reviewer findings → resolutions)

1. HIGH migration save swallowed errors → promotion now throws (fetch+save);
   replay on next launch. Locked in tests via on-disk reopen migration.
2. HIGH `isInUse` blind spot on the legacy column → promotion now strips
   `appList` after copying (asserted in the migration test), closing the gap at
   the source.
3. MEDIUM ordered relationship compare churned models → set compare in
   `RuleDraft.apply`.
4. MEDIUM union decode without authorization yields nil → documented +
   `Diag.log` event when a multi-list combined decode is empty (bogus bytes or
   missing authorization); device-only validation of true unions.
5. LOW init relationship writes / doc typo → cleaned.

## Known limits / device verification pending

- The true union of two non-empty selections requires decodable Screen Time
  tokens — only verifiable on device with real Family Controls authorization
  (bogus unit-test bytes decode to an empty selection by design).
- The "N Lists · M Apps" count double-counts apps shared between lists.
