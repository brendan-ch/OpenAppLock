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
}
