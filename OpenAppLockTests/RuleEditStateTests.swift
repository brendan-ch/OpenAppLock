//
//  RuleEditStateTests.swift
//  OpenAppLockTests
//

import SwiftData
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Rule editor outstanding-edits detection")
struct RuleEditStateTests {
    @Test("A freshly opened editor has no outstanding edits")
    func untouchedHasNoEdits() {
        let draft = RuleDraft(kind: .schedule)
        #expect(!RuleEditState.hasOutstandingEdits(original: draft, current: draft))
    }

    @Test("Renaming the rule counts as an outstanding edit")
    func renameIsAnEdit() {
        let original = RuleDraft(kind: .schedule)
        var current = original
        current.name = "Focus Time"
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("A trailing-whitespace name change counts as an edit (raw comparison)")
    func whitespaceRenameIsAnEdit() {
        let original = RuleDraft(kind: .schedule)
        var current = original
        current.name = original.name + " "
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Changing which days the rule covers counts as an outstanding edit")
    func dayChangeIsAnEdit() {
        let original = RuleDraft(kind: .schedule)  // weekdays by default
        var current = original
        current.days = Weekday.everyDay
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Toggling Hard Mode counts as an outstanding edit")
    func hardModeToggleIsAnEdit() {
        let original = RuleDraft(kind: .schedule)
        var current = original
        current.hardMode.toggle()
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Changing a schedule's time window counts as an outstanding edit")
    func scheduleTimeChangeIsAnEdit() {
        let original = RuleDraft(kind: .schedule)
        var current = original
        current.scheduleConfig.startMinutes += 30
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Changing a time limit's minutes counts as an outstanding edit")
    func timeLimitChangeIsAnEdit() {
        let original = RuleDraft(kind: .timeLimit)
        var current = original
        current.timeLimitConfig.dailyLimitMinutes += 15
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Changing an open limit's count counts as an outstanding edit")
    func openLimitChangeIsAnEdit() {
        let original = RuleDraft(kind: .openLimit)
        var current = original
        current.openLimitConfig.maxOpens += 1
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Editing a field then reverting it leaves no outstanding edits")
    func revertedEditIsClean() {
        let original = RuleDraft(kind: .schedule)
        var current = original
        current.name = "Temporary"
        current.name = original.name
        #expect(!RuleEditState.hasOutstandingEdits(original: original, current: current))
    }

    @Test("Choosing a different app list counts as an outstanding edit")
    func appListChangeIsAnEdit() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions", selectionCount: 3)
        context.insert(list)

        let original = RuleDraft(kind: .schedule)  // appList == nil
        var current = original
        current.appList = list
        #expect(RuleEditState.hasOutstandingEdits(original: original, current: current))
    }
}
