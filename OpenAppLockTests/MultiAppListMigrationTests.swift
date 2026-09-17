//
//  MultiAppListMigrationTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing
@testable import OpenAppLock
import SwiftData

@MainActor
@Suite("v2 to v3 migration tests")
struct V2ToV3MigrationTests {
    /// A fresh on-disk store per test under the session temp dir. Existing V1→V2
    /// tests still rely on shared single containers; the V2→V3 path needs
    /// migration across an actual reopen to be exercised.
    private func makeStoreURL() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("migration-v2-\(UUID().uuidString).sqlite")
        return url
    }

    private func makeV2Store(url: URL, ruleName: String, attachList: Bool) throws -> UUID {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OpenAppLockSchemaV2.self),
            migrationPlan: OpenAppLockSchemaMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let rule = OpenAppLockSchemaV2.BlockingRule(name: ruleName)
        var ruleID = rule.id
        if attachList {
            let list = OpenAppLockSchemaV2.AppList(name: "Distractions", selectionCount: 3)
            context.insert(list)
            context.insert(rule)
            rule.appList = list
            ruleID = rule.id
        } else {
            context.insert(rule)
        }
        try context.save()
        return ruleID
    }

    private func migratedV3Store(url: URL) throws -> (
        context: ModelContext,
        container: ModelContainer
    ) {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OpenAppLockSchemaV3.self),
            migrationPlan: OpenAppLockSchemaMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        return (context, container)
    }

    @Test("Rule with a single appList migrates to appLists containing it")
    func singleAppListRuleMigrates() throws {
        let url = makeStoreURL()
        let ruleID = try makeV2Store(
            url: url, ruleName: "Work Time", attachList: true)

        let (context, container) = try migratedV3Store(url: url)

        let fetched = try context.fetch(FetchDescriptor<OpenAppLockSchemaV3.BlockingRule>())
        let migrated = try #require(fetched.first { $0.id == ruleID })
        #expect(migrated.appLists.count == 1)
        #expect(migrated.appLists.first?.name == "Distractions")
        // Promotion strips the legacy column once copied.
        #expect(migrated.appList == nil)
    }

    @Test("Rule without an app list migrates to an empty appLists selection")
    func ruleWithoutAppListMigrates() throws {
        let url = makeStoreURL()
        let ruleID = try makeV2Store(
            url: url, ruleName: "Work Time", attachList: false)

        let (context, container) = try migratedV3Store(url: url)

        let fetched = try context.fetch(FetchDescriptor<OpenAppLockSchemaV3.BlockingRule>())
        let migrated = try #require(fetched.first { $0.id == ruleID })
        #expect(migrated.appLists.isEmpty)
    }
}
