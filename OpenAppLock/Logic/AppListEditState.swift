//
//  AppListEditState.swift
//  OpenAppLock
//

import FamilyControls

/// Decides whether an open app-list editor has unsaved work. The editor uses
/// this to gate the "Discard Changes?" confirmation: closing with outstanding
/// edits prompts before throwing them away, the standard iOS pattern.
enum AppListEditState {
    /// Outstanding edits exist when the name changed or the chosen apps changed
    /// from what the editor opened with.
    static func hasOutstandingEdits(
        originalName: String,
        currentName: String,
        originalSelection: FamilyActivitySelection,
        currentSelection: FamilyActivitySelection
    ) -> Bool {
        if currentName != originalName { return true }
        return !selectionsMatch(originalSelection, currentSelection)
    }

    /// Two selections match when their app, category, and web-domain token sets
    /// are equal. Compared as sets so token ordering never matters (unlike the
    /// encoded `Data`, whose byte order isn't guaranteed stable).
    static func selectionsMatch(
        _ lhs: FamilyActivitySelection, _ rhs: FamilyActivitySelection
    ) -> Bool {
        lhs.applicationTokens == rhs.applicationTokens
            && lhs.categoryTokens == rhs.categoryTokens
            && lhs.webDomainTokens == rhs.webDomainTokens
    }
}
