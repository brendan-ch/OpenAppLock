//
//  AppListTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

// Note: every test wires `rule.appList` only after both models are inserted —
// SwiftData relationships must not be written on unmanaged instances
// (see BlockingRule.appList).

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
        let list = AppList(name: "Distractions")
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appList = list
        try context.save()

        context.delete(list)
        try context.save()

        let rules = try context.fetch(FetchDescriptor<BlockingRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.appList == nil)
    }

    @Test("Deleting a rule keeps its list")
    func deletingRuleKeepsList() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions")
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appList = list
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
        rule.appList = used
        try context.save()

        #expect(AppList.isInUse(used, context: context))
        #expect(!AppList.isInUse(unused, context: context))
    }
}

@MainActor
@Suite("Legacy selection → AppList migration")
struct AppListMigrationTests {
    /// Simulates a rule decoded from a pre-app-list store: a plain rule whose
    /// legacy inline-selection columns are populated.
    private func legacyRule(name: String, selectionData: Data, selectionCount: Int) -> BlockingRule {
        let rule = BlockingRule(name: name)
        rule.selectionData = selectionData
        rule.selectionCount = selectionCount
        return rule
    }

    @Test("Rules with legacy inline selections get a list named after them")
    func createsListsFromLegacySelections() throws {
        let context = try makeInMemoryContext()
        let rule = BlockingRule(name: "Work Time")
        rule.selectionData = Data([1])
        rule.selectionCount = 3
        context.insert(rule)
        try context.save()

        AppListMigration.run(in: context)

        let lists = try context.fetch(FetchDescriptor<AppList>())
        #expect(lists.count == 1)
        let list = try #require(rule.appList)
        #expect(list.name == "Work Time Apps")
        #expect(list.selectionData == Data([1]))
        #expect(list.selectionCount == 3)
        // The legacy inline copy is cleared so migration never re-runs.
        #expect(rule.selectionData == nil)
    }

    @Test("Rules with identical selections share one list")
    func sharesListForIdenticalSelections() throws {
        let context = try makeInMemoryContext()
        let first = legacyRule(name: "Work Time", selectionData: Data([7]), selectionCount: 2)
        let second = legacyRule(name: "Sleep", selectionData: Data([7]), selectionCount: 2)
        let different = legacyRule(name: "Gym", selectionData: Data([9]), selectionCount: 1)
        context.insert(first)
        context.insert(second)
        context.insert(different)
        try context.save()

        AppListMigration.run(in: context)

        let lists = try context.fetch(FetchDescriptor<AppList>())
        #expect(lists.count == 2)
        #expect(first.appList === second.appList)
        #expect(first.appList !== different.appList)
    }

    @Test("Migration is idempotent and skips selection-less rules")
    func idempotentAndSkipsEmpty() throws {
        let context = try makeInMemoryContext()
        let legacy = legacyRule(name: "Work Time", selectionData: Data([1]), selectionCount: 1)
        let empty = BlockingRule(name: "No Apps")
        context.insert(legacy)
        context.insert(empty)
        try context.save()

        AppListMigration.run(in: context)
        AppListMigration.run(in: context)

        let lists = try context.fetch(FetchDescriptor<AppList>())
        #expect(lists.count == 1)
        #expect(empty.appList == nil)
    }
}

@MainActor
@Suite("Rule drafts with app lists")
struct AppListDraftTests {
    @Test("Drafts carry the rule's app list and apply it back")
    func draftCarriesAppList() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions", selectionCount: 4)
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appList = list

        var draft = RuleDraft(rule: rule)
        #expect(draft.appList === list)

        draft.name = "Other"
        let other = draft.insertRule(into: context)
        #expect(other.appList === list)
        #expect(other.name == "Other")
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
@Suite("App-list editing under Hard Mode")
struct AppListEditingPolicyTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    @Test("App lists are locked while any hard-mode rule is actively blocking")
    func lockedDuringHardModeSession() {
        let hard = BlockingRule(name: "Locked In", hardMode: true)
        let soft = BlockingRule(name: "Work Time")
        #expect(
            !RulePolicy.canEditAppLists(rules: [hard, soft], at: mondayDuringWork, calendar: utc))
    }

    @Test("App lists stay editable when no hard-mode rule is blocking")
    func editableWithoutHardSession() {
        let softActive = BlockingRule(name: "Work Time")
        let hardInactive = BlockingRule(name: "Locked In", hardMode: true)
        #expect(
            RulePolicy.canEditAppLists(
                rules: [softActive, hardInactive], at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canEditAppLists(rules: [], at: mondayDuringWork, calendar: utc))
    }

    @Test("A disabled hard-mode rule does not lock app lists")
    func disabledHardRuleDoesNotLock() {
        let rule = BlockingRule(name: "Locked In", isEnabled: false, hardMode: true)
        #expect(RulePolicy.canEditAppLists(rules: [rule], at: mondayDuringWork, calendar: utc))
    }
}

@MainActor
@Suite("Enforcement reads selections through app lists")
struct AppListEnforcementTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)

    @Test("The rule's app-list selection reaches the shield layer")
    func forwardsAppListSelection() throws {
        let context = try makeInMemoryContext()
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let list = AppList(name: "Distractions", selectionData: Data([1, 2, 3]))
        let rule = BlockingRule(name: "Work Time")
        context.insert(list)
        context.insert(rule)
        rule.appList = list

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.appliedSelectionData[rule.id] == Data([1, 2, 3]))
    }
}
