//
//  AppListTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

// Note: every test wires a relationship only after both models are inserted —
// SwiftData relationships must not be written on unmanaged instances
// (see BlockingRule.appLists).

@MainActor
@Suite("AppList model & relationship")
struct AppListModelTests {
    @Test("App lists persist and fetch through SwiftData")
    func persistence() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions", selectionData: Data([1, 2]), selectionCount: 2)
        context.insert(list)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppList>())
        #expect(fetched.count == 1)
        let saved = try #require(fetched.first)
        #expect(saved.name == "Distractions")
        #expect(saved.selectionCount == 2)
        #expect(saved.selectionData == Data([1, 2]))
    }

    @Test("Deleting a list detaches it from its rules")
    func deletingListDetachesRules() throws {
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
        #expect(!AppList.isInUse(first, context: context))
        #expect(AppList.isInUse(second, context: context))
    }

    @Test("Deleting a rule keeps its list")
    func deletingRuleKeepsList() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions")
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appLists = [list]
        try context.save()

        context.delete(rule)
        try context.save()

        let lists = try context.fetch(FetchDescriptor<AppList>())
        #expect(lists.count == 1)
    }

    @Test("Lists report whether any rule uses them")
    func usageQuery() throws {
        let context = try makeInMemoryContext()
        let used = AppList(name: "Used")
        let unused = AppList(name: "Unused")
        let rule = BlockingRule(name: "Work Time")
        context.insert(used)
        context.insert(unused)
        context.insert(rule)
        rule.appLists = [used]
        try context.save()

        #expect(AppList.isInUse(used, context: context))
        #expect(!AppList.isInUse(unused, context: context))
    }

    @Test("Combined selection: single data carrier passes through, none yields nil")
    func combinedSelectionEdgeCases() throws {
        let carrier = AppList(name: "Carrier", selectionData: Data([9, 9]))
        let empty = AppList(name: "Empty")
        let fallbackRule = BlockingRule(name: "Fallback")
        fallbackRule.appLists = [carrier, empty]
        #expect(fallbackRule.combinedSelectionData == Data([9, 9]))
        #expect(fallbackRule.dto.selectionData == Data([9, 9]))

        let emptyRule = BlockingRule(name: "Empty")
        emptyRule.appLists = [AppList(name: "Empty")]
        #expect(emptyRule.combinedSelectionData == nil)
        #expect(emptyRule.dto.selectionData == nil)
    }

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
@Suite("Rule drafts with app lists")
struct AppListDraftTests {
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
        #expect(other.name == "Other")
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

    @Test("Limit drafts structurally cannot carry a selection mode")
    func limitDraftsHaveNoSelectionMode() {
        // The sum type makes Block / Allow Only a Schedule-only option: a limit
        // draft's configuration has no selection mode to force back to Block.
        #expect(RuleDraft(kind: .timeLimit).configuration.scheduleConfig == nil)
        #expect(RuleDraft(kind: .openLimit).configuration.scheduleConfig == nil)

        // And the rule built from a limit draft is always Block.
        let rule = BlockingRule(
            name: "Time Keeper", configuration: RuleDraft(kind: .timeLimit).configuration)
        #expect(rule.selectionMode == .block)
    }

    @Test("Allow Only survives on schedule rules")
    func keepsAllowOnlyForSchedule() {
        var draft = RuleDraft(kind: .schedule)
        draft.scheduleConfig.selectionMode = .allowOnly
        #expect(draft.sanitized().scheduleConfig.selectionMode == .allowOnly)
    }
}

@MainActor
@Suite("App-list editing under Lock While Blocking")
struct AppListEditingPolicyTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    @Test("App lists are locked while any hard-mode rule is actively blocking")
    func lockedDuringHardModeSession() {
        let hard = BlockingRule(name: "Locked In", hardMode: true)
        let soft = BlockingRule(name: "Work Time")
        #expect(
            !RulePolicy.canEditAppLists(snapshots: [hard, soft].map(\.dto), at: mondayDuringWork, calendar: utc))
    }

    @Test("App lists stay editable when no hard-mode rule is blocking")
    func editableWithoutHardSession() {
        let softActive = BlockingRule(name: "Work Time")
        let hardInactive = BlockingRule(name: "Locked In", hardMode: true)
        #expect(
            RulePolicy.canEditAppLists(
                snapshots: [softActive, hardInactive].map(\.dto), at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canEditAppLists(snapshots: [], at: mondayDuringWork, calendar: utc))
    }

    @Test("A disabled hard-mode rule does not lock app lists")
    func disabledHardRuleDoesNotLock() {
        let rule = BlockingRule(name: "Locked In", isEnabled: false, hardMode: true)
        #expect(RulePolicy.canEditAppLists(snapshots: [rule].map(\.dto), at: mondayDuringWork, calendar: utc))
    }
}

@MainActor
@Suite("Enforcement reads selections through app lists")
struct AppListEnforcementTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)

    @Test("The rule's app-list selection reaches the shield layer")
    func forwardsAppListSelection() async throws {
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

        await enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(shields.appliedSelectionData[rule.id] == data)
    }
}

@MainActor
@Suite("App-list count labels")
struct AppListCountLabelTests {
    /// Inserts a list plus `ruleCount` rules pointing at it. The relationship is
    /// wired only after every model is in the context — SwiftData forbids
    /// relationship writes on unmanaged instances (see BlockingRule.appLists).
    private func makeList(
        selectionCount: Int = 0,
        ruleCount: Int,
        in context: ModelContext
    ) throws -> AppList {
        let list = AppList(name: "Distractions", selectionCount: selectionCount)
        context.insert(list)
        for index in 0..<ruleCount {
            let rule = BlockingRule(name: "Rule \(index + 1)")
            context.insert(rule)
            rule.appLists = [list]
        }
        try context.save()
        return list
    }

    @Test("ruleCountLabel pluralizes a list with no associated rules")
    func ruleCountLabelForNoRules() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(ruleCount: 0, in: context)
        #expect(list.ruleCountLabel == "0 Rules")
    }

    @Test("ruleCountLabel is singular for exactly one associated rule")
    func ruleCountLabelForOneRule() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(ruleCount: 1, in: context)
        #expect(list.ruleCountLabel == "1 Rule")
    }

    @Test("ruleCountLabel pluralizes multiple associated rules")
    func ruleCountLabelForManyRules() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(ruleCount: 3, in: context)
        #expect(list.ruleCountLabel == "3 Rules")
    }

    @Test("appAndRuleCountLabel joins plural app and rule counts")
    func appAndRuleCountLabelPlural() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(selectionCount: 4, ruleCount: 2, in: context)
        #expect(list.appAndRuleCountLabel == "4 Apps · 2 Rules")
    }

    @Test("appAndRuleCountLabel uses singular app and rule forms")
    func appAndRuleCountLabelSingular() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(selectionCount: 1, ruleCount: 1, in: context)
        #expect(list.appAndRuleCountLabel == "1 App · 1 Rule")
    }

    @Test("appAndRuleCountLabel pluralizes each half independently")
    func appAndRuleCountLabelMixedPlurality() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(selectionCount: 1, ruleCount: 3, in: context)
        #expect(list.appAndRuleCountLabel == "1 App · 3 Rules")
    }

    @Test("appAndRuleCountLabel reports an empty list as zero apps and zero rules")
    func appAndRuleCountLabelEmpty() throws {
        let context = try makeInMemoryContext()
        let list = try makeList(selectionCount: 0, ruleCount: 0, in: context)
        #expect(list.appAndRuleCountLabel == "0 Apps · 0 Rules")
    }

    @Test("appListSummary keeps the single-list format and counts lists for multiple")
    func appListSummaryByListCount() {
        let single = BlockingRule(name: "Work Time")
        single.appLists = [AppList(name: "Distractions", selectionCount: 4)]
        #expect(
            single.appListSummary
                == CopyKey.ruleDetailAppListSummaryFormat.string("Distractions", "4 Apps"))

        let multiple = BlockingRule(name: "Work Time")
        multiple.appLists = [
            AppList(name: "Distractions", selectionCount: 4),
            AppList(name: "Social", selectionCount: 1),
        ]
        #expect(multiple.appListSummary == "2 Lists · 5 Apps")
    }

    @Test("appListSummary shows the no-apps placeholder with nothing selected")
    func appListSummaryEmptySelection() {
        let rule = BlockingRule(name: "Work Time")
        #expect(rule.appListSummary == "No apps")
    }
}
