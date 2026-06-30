//
//  RuleEditState.swift
//  OpenAppLock
//

/// Decides whether an open rule editor has unsaved work. The rule detail view
/// uses this to gate the "Discard Changes?" confirmation: leaving edit mode
/// with outstanding edits prompts before throwing them away, the standard iOS
/// pattern (the counterpart to `AppListEditState` for the app-list editor).
enum RuleEditState {
    /// Outstanding edits exist when any user-editable field of the draft differs
    /// from what the editor opened with. `RuleDraft` is `Equatable`, so a single
    /// raw comparison covers the name, days, Hard Mode, kind configuration, and
    /// the chosen app list at once. The comparison is raw — not sanitized — so a
    /// trailing-whitespace name edit still counts, matching `AppListEditState`.
    static func hasOutstandingEdits(original: RuleDraft, current: RuleDraft) -> Bool {
        current != original
    }
}
