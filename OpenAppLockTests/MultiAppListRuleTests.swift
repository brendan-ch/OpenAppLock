//
//  MultiAppListRuleTests.swift
//  OpenAppLockTests
//

import FamilyControls
import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Multi app-list rules")
struct MultiAppListRuleTests {
    @Test("Drafts carry every selected list and apply them back")
    func draftCarriesAllLists() throws {
        let context = try makeInMemoryContext()
        let first = AppList(name: "Distractions", selectionCount: 3)
        let second = AppList(name: "Social", selectionCount: 2)
        let rule = BlockingRule(name: "Work Time")
        context.insert(first)
        context.insert(second)
        context.insert(rule)
        rule.appLists = [first, second]
        try context.save()

        var draft = RuleDraft(rule: rule)
        #expect(Set(draft.appLists.map(\.id)) == Set([first.id, second.id]))

        draft.name = "Other"
        let other = draft.insertRule(into: context)
        #expect(Set(other.appLists.map(\.id)) == Set([first.id, second.id]))
    }

    @Test("Draft apply replaces the rule's previous selection entirely")
    func draftApplyReplacesLists() throws {
        let context = try makeInMemoryContext()
        let first = AppList(name: "First")
        let second = AppList(name: "Second")
        let third = AppList(name: "Third")
        let rule = BlockingRule(name: "Work Time")
        context.insert(first)
        context.insert(second)
        context.insert(third)
        context.insert(rule)
        rule.appLists = [first, second]
        try context.save()

        var draft = RuleDraft(rule: rule)
        draft.appLists = [third]
        draft.apply(to: rule)
        #expect(rule.appLists.map(\.id) == [third.id])
    }

    @Test("Deleting a list leaves the rule with its remaining lists")
    func deletingListKeepsRemainingLists() throws {
        let context = try makeInMemoryContext()
        let first = AppList(name: "First")
        let second = AppList(name: "Second")
        let rule = BlockingRule(name: "Work Time")
        context.insert(first)
        context.insert(second)
        context.insert(rule)
        rule.appLists = [first, second]
        try context.save()

        context.delete(first)
        try context.save()

        #expect(rule.appLists.map(\.id) == [second.id])
        #expect(AppList.isInUse(second, context: context))
        #expect(!AppList.isInUse(first, context: context))
    }

    @Test("A single selected list's selection data reaches enforcement unchanged")
    func singleListSelectionPassthrough() async throws {
        let context = try makeInMemoryContext()
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let data = Data([1, 2, 3])
        let list = AppList(name: "Distractions", selectionData: data)
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appLists = [list]
        try context.save()

        #expect(rule.combinedSelectionData == data)
        #expect(rule.dto.selectionData == data)

        await enforcer.refresh(rules: [rule], at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(shields.appliedSelectionData[rule.id] == data)
    }

    @Test("Combined selection falls back to the only list carrying data")
    func combinedSelectionFallsBackToSingleDataCarrier() throws {
        let carrier = AppList(name: "Carrier", selectionData: Data([9, 9]))
        let empty = AppList(name: "Empty")
        let rule = BlockingRule(name: "Work Time")
        rule.appLists = [carrier, empty]
        #expect(rule.combinedSelectionData == Data([9, 9]))
    }

    @Test("Combined selection is nil when no selected list has data")
    func combinedSelectionNilWithoutData() throws {
        let rule = BlockingRule(name: "Work Time")
        rule.appLists = [AppList(name: "Empty")]
        #expect(rule.combinedSelectionData == nil)
        #expect(rule.dto.selectionData == nil)
    }

    /// Real token fabrication is impossible without Screen Time authorization,
    /// so a true union of two non-empty selections can only be verified on
    /// device. This test covers what is testable here: two lists with data
    /// produce *combined* selection data (never a bare passthrough), which
    /// still decodes to a selection even if the bytes are bogus.
    @Test("Two data-carrying lists produce combined selection data")
    func twoDataCarriersProduceCombinedData() throws {
        let first = AppList(name: "First", selectionData: Data([1, 2, 3]))
        let second = AppList(name: "Second", selectionData: Data([4, 5, 6]))
        let rule = BlockingRule(name: "Work Time")
        rule.appLists = [first, second]
        #expect(rule.combinedSelectionData != first.selectionData)
        #expect(rule.combinedSelectionData != second.selectionData)
    }
}

@MainActor
@Suite("Projected app-list labels")
struct ProjectedAppListLabelTests {
    @Test("The detail sheet's app summary shows a single list as before")
    func singleListSummary() {
        let list = AppList(name: "Distractions", selectionCount: 4)
        let rule = BlockingRule(name: "Work Time")
        rule.appLists = [list]
        #expect(
            rule.appListSummary
                == CopyKey.ruleDetailAppListSummaryFormat.string("Distractions", "4 Apps"))
    }

    @Test("The detail sheet's app summary counts lists and apps for multiple lists")
    func multipleListSummary() {
        let first = AppList(name: "Distractions", selectionCount: 4)
        let second = AppList(name: "Social", selectionCount: 1)
        let rule = BlockingRule(name: "Work Time")
        rule.appLists = [first, second]
        #expect(rule.appListSummary == "2 Lists · 5 Apps")
    }

    @Test("An empty selection shows the no-apps placeholder")
    func emptySelectionSummary() {
        let rule = BlockingRule(name: "Work Time")
        #expect(rule.appListSummary == "No apps")
    }
}
