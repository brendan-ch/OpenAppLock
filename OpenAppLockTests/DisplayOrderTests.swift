//
//  DisplayOrderTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

// The display order shared by every user-editable list: rules (the Rules tab,
// grouped by kind, and the Home tab rows) and app lists (the library / picker).
// All three views fetch with `displayOrder`, so these tests fetch the same way
// — `FetchDescriptor(sortBy:)` is exactly the mechanism `@Query(sort:)` uses.

@MainActor
@Suite("Rule display order")
struct RuleDisplayOrderTests {
    private func names(fetchedWith context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<BlockingRule>(sortBy: BlockingRule.displayOrder))
            .map(\.name)
    }

    @Test("Rules sort alphabetically by name, not by creation order")
    func alphabeticalNotInsertionOrder() throws {
        let context = try makeInMemoryContext()
        for name in ["Charlie", "Alpha", "Bravo"] {
            context.insert(BlockingRule(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["Alpha", "Bravo", "Charlie"])
    }

    @Test("Ordering is case-insensitive (apple before Banana, not ASCII order)")
    func caseInsensitive() throws {
        let context = try makeInMemoryContext()
        for name in ["Banana", "apple"] {
            context.insert(BlockingRule(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["apple", "Banana"])
    }

    @Test("Ordering is numeric-aware (Focus 2 before Focus 10)")
    func localizedNumeric() throws {
        let context = try makeInMemoryContext()
        for name in ["Focus 10", "Focus 2"] {
            context.insert(BlockingRule(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["Focus 2", "Focus 10"])
    }

    @Test("Ordering folds diacritics (Éclair sorts among the E's, before Zen)")
    func diacriticFolding() throws {
        let context = try makeInMemoryContext()
        for name in ["Zen", "Éclair"] {
            context.insert(BlockingRule(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["Éclair", "Zen"])
    }

    @Test("Equal names break the tie by creation date, oldest first")
    func equalNamesTieBreakByCreatedAt() throws {
        let context = try makeInMemoryContext()
        let older = BlockingRule(name: "Focus", createdAt: date(2025, 1, 6, 10, 0))
        let newer = BlockingRule(name: "Focus", createdAt: date(2025, 1, 6, 11, 0))
        // Insert newest-first so only the tie-break (not insertion order) can
        // produce the expected oldest-first result.
        context.insert(newer)
        context.insert(older)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<BlockingRule>(sortBy: BlockingRule.displayOrder))
        #expect(fetched.map(\.id) == [older.id, newer.id])
    }

    @Test("Empty and single-item fetches are trivially ordered")
    func boundaries() throws {
        let context = try makeInMemoryContext()
        #expect(try names(fetchedWith: context) == [])

        context.insert(BlockingRule(name: "Only One"))
        try context.save()
        #expect(try names(fetchedWith: context) == ["Only One"])
    }
}

@MainActor
@Suite("App list display order")
struct AppListDisplayOrderTests {
    private func names(fetchedWith context: ModelContext) throws -> [String] {
        try context.fetch(FetchDescriptor<AppList>(sortBy: AppList.displayOrder))
            .map(\.name)
    }

    @Test("App lists sort alphabetically by name, not by creation order")
    func alphabeticalNotInsertionOrder() throws {
        let context = try makeInMemoryContext()
        for name in ["Productivity", "Distractions", "Social"] {
            context.insert(AppList(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["Distractions", "Productivity", "Social"])
    }

    @Test("Ordering is case-insensitive (apps before Books, not ASCII order)")
    func caseInsensitive() throws {
        let context = try makeInMemoryContext()
        for name in ["Books", "apps"] {
            context.insert(AppList(name: name))
        }
        try context.save()

        #expect(try names(fetchedWith: context) == ["apps", "Books"])
    }

    @Test("Equal names break the tie by creation date, oldest first")
    func equalNamesTieBreakByCreatedAt() throws {
        let context = try makeInMemoryContext()
        let older = AppList(name: "Focus", createdAt: date(2025, 1, 6, 10, 0))
        let newer = AppList(name: "Focus", createdAt: date(2025, 1, 6, 11, 0))
        context.insert(newer)
        context.insert(older)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<AppList>(sortBy: AppList.displayOrder))
        #expect(fetched.map(\.id) == [older.id, newer.id])
    }
}
