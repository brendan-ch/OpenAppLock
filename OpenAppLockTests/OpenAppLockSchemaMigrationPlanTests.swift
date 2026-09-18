//
//  OpenAppLockSchemaMigrationPlanTests.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.11.
//

import Foundation
import Testing
@testable import OpenAppLock
import SwiftData

@MainActor
@Suite("v1 to v2 migration tests")
struct V1ToV2MigrationTests {
    /// Since we are operating on the V1 container, we need a custom `ModelContext`.
    func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OpenAppLockSchemaV1.self),
            migrationPlan: OpenAppLockSchemaMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        return ModelContext(container)
    }
    
    @Test("Rule with 23:45-23:50 changes to 23:45-00:00")
    func testMinimumDurationMigrationWrapsToMidnight() throws {
        let context = try makeModelContext()
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 23 * 60 + 45, endMinutes: 23 * 60 + 50)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 23 * 60 + 45)
        #expect(updatedModel.schedule.endMinutes == 0)
        #expect(changed.count == 1)
    }
    
    @Test("Rule with 23:50-23:51 changes to 23:45-00:00")
    func testMidnightStartShiftRunsBeforeMinimumDurationMigration() throws {
        let context = try makeModelContext()
        
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 23 * 60 + 50, endMinutes: 23 * 60 + 51)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 23 * 60 + 45)
        #expect(updatedModel.schedule.endMinutes == 0)
        #expect(changed.count == 1)
    }

    @Test("Rule with 09:00-09:01 changes to 09:00-09:15")
    func testMinimumDurationMigrationRunsBeforeIntervalClamp() throws {
        let context = try makeModelContext()
        
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 9 * 60, endMinutes: 9 * 60 + 1)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 9 * 60)
        #expect(updatedModel.schedule.endMinutes == 9 * 60 + 15)
        #expect(changed.count == 1)
    }
    
    @Test("Rule with 09:00-09:16 changes to 09:00-09:15")
    func testIntervalClamp() throws {
        let context = try makeModelContext()
        
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 9 * 60, endMinutes: 9 * 60 + 16)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 9 * 60)
        #expect(updatedModel.schedule.endMinutes == 9 * 60 + 15)
        #expect(changed.count == 1)
    }
    
    @Test("Rule with 23:56-23:54 changes to 23:45-23:40")
    func testStartAndEndTimeShiftForMidnightScheduledRule() throws {
        let context = try makeModelContext()
        
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 23 * 60 + 56, endMinutes: 23 * 60 + 54)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 23 * 60 + 45)
        #expect(updatedModel.schedule.endMinutes == 23 * 60 + 40)
        #expect(changed.count == 1)
    }
    
    @Test("Rule with 00:02-00:01 changes to 00:00-00:00")
    func testIntervalClampForOverlappingRule() throws {
        let context = try makeModelContext()
        
        let model = OpenAppLockSchemaV1.BlockingRule(name: "Test", configuration: .schedule(ScheduleConfig(startMinutes: 2, endMinutes: 1)))
        context.insert(model)
        let changed = try MigrationHelpers.prepareV1DataForMigration(context)
        
        guard let updatedModel = context.model(for: model.id) as? OpenAppLockSchemaV1.BlockingRule else {
            Issue.record("Unable to find matching BlockingRule \(model.id)")
            return
        }
        
        #expect(updatedModel.schedule.startMinutes == 0)
        #expect(updatedModel.schedule.endMinutes == 0)
        #expect(changed.count == 1)
    }
}

@MainActor
@Suite("v2 to v3 migration tests")
struct V2ToV3MigrationTests {
    private func makeStoreURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("migration-v2-\(UUID().uuidString).sqlite")
    }

    /// Fresh on-disk V2 store; an actual reopen is what exercises the
    /// V2→V3 migration.
    private func makeV2Store(
        url: URL, attachedRuleID: inout UUID?, detachedRuleID: inout UUID
    ) throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OpenAppLockSchemaV2.self),
            migrationPlan: OpenAppLockSchemaMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let attached = OpenAppLockSchemaV2.BlockingRule(name: "Attached")
        let list = OpenAppLockSchemaV2.AppList(name: "Distractions", selectionCount: 3)
        context.insert(list)
        context.insert(attached)
        attached.appList = list
        attachedRuleID = attached.id
        let detached = OpenAppLockSchemaV2.BlockingRule(name: "Detached")
        context.insert(detached)
        detachedRuleID = detached.id
        try context.save()
    }

    private func migratedV3Store(url: URL) throws -> (ModelContext, ModelContainer) {
        let container = try ModelContainer(
            for: Schema(versionedSchema: OpenAppLockSchemaV3.self),
            migrationPlan: OpenAppLockSchemaMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        return (ModelContext(container), container)
    }

    @Test("appList migrations: single-list rule promoted and stripped; unlisted rule stays empty")
    func appListPromotionAcrossReopen() throws {
        let url = makeStoreURL()
        var attachedRuleID: UUID?
        var detachedRuleID = UUID()
        try makeV2Store(url: url, attachedRuleID: &attachedRuleID, detachedRuleID: &detachedRuleID)

        let (context, _) = try migratedV3Store(url: url)
        let rules = try context.fetch(FetchDescriptor<OpenAppLockSchemaV3.BlockingRule>())

        let attached = try #require(rules.first { $0.id == attachedRuleID })
        #expect(attached.appLists.map(\.name) == ["Distractions"])
        #expect(attached.appList == nil)

        let detached = try #require(rules.first { $0.id == detachedRuleID })
        #expect(detached.appLists.isEmpty)
    }
}
