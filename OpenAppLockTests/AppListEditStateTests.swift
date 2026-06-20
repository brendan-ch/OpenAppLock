//
//  AppListEditStateTests.swift
//  OpenAppLockTests
//

import FamilyControls
import Testing

@testable import OpenAppLock

@Suite("App-list editor outstanding-edits detection")
struct AppListEditStateTests {
    @Test("A freshly opened editor has no outstanding edits")
    func untouchedHasNoEdits() {
        #expect(
            !AppListEditState.hasOutstandingEdits(
                originalName: "",
                currentName: "",
                originalSelection: FamilyActivitySelection(),
                currentSelection: FamilyActivitySelection()
            )
        )
        #expect(
            !AppListEditState.hasOutstandingEdits(
                originalName: "Distractions",
                currentName: "Distractions",
                originalSelection: FamilyActivitySelection(),
                currentSelection: FamilyActivitySelection()
            )
        )
    }

    @Test("Renaming the list counts as an outstanding edit")
    func renameIsAnEdit() {
        #expect(
            AppListEditState.hasOutstandingEdits(
                originalName: "",
                currentName: "Focus Apps",
                originalSelection: FamilyActivitySelection(),
                currentSelection: FamilyActivitySelection()
            )
        )
        #expect(
            AppListEditState.hasOutstandingEdits(
                originalName: "Distractions",
                currentName: "Distractions ",
                originalSelection: FamilyActivitySelection(),
                currentSelection: FamilyActivitySelection()
            )
        )
    }

    @Test("Two empty selections match regardless of name when the name is unchanged")
    func emptySelectionsMatch() {
        #expect(
            AppListEditState.selectionsMatch(
                FamilyActivitySelection(), FamilyActivitySelection()
            )
        )
    }
}
