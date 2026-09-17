//
//  OpenAppLockSchemaMigrationPlan.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.09.
//

import SwiftData
import Foundation

enum OpenAppLockSchemaMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    static var schemas: [any VersionedSchema.Type] = [
        OpenAppLockSchemaV1.self,
        OpenAppLockSchemaV2.self,
        OpenAppLockSchemaV3.self
    ]

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: OpenAppLockSchemaV1.self,
        toVersion: OpenAppLockSchemaV2.self,
        willMigrate: { context in
            Diag.log(.migration, "migrating schema from V1 to V2")

            let changed = try MigrationHelpers.prepareV1DataForMigration(context)
            if changed.count > 0 {
                AppGroup.defaults.set(true, forKey: AppGroup.migrationDataChangedKey)
                Diag.log(.migration, "clamped schedule rule times; flagged migrated-data banner")
            }
        }, didMigrate: nil
    )

    /// Custom V2→V3 stage: `didMigrate` promotes each rule's legacy `appList`
    /// into the new `appLists` array.
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: OpenAppLockSchemaV2.self,
        toVersion: OpenAppLockSchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            Diag.log(.migration, "migrating schema from V2 to V3")
            try MigrationHelpers.promoteV2RuleAppLists(context)
        }
    )
}

enum MigrationHelpers {
    /// Perform the schema migration and get the IDs of rules that changed.
    static func prepareV1DataForMigration(_ context: ModelContext) throws -> Set<UUID> {
        let latestAllowedStartMinutes = 23 * 60 + 45
        let minimumRuleDurationMinutes = 15

        var changed: Set<UUID> = Set()
        
        let rules = try context.fetch(FetchDescriptor<OpenAppLockSchemaV1.BlockingRule>())
        for rule in rules where rule.kind == .schedule {
            if rule.startMinutes > latestAllowedStartMinutes {
                let diff = rule.startMinutes - latestAllowedStartMinutes
                rule.startMinutes = latestAllowedStartMinutes
                rule.endMinutes = rule.endMinutes - diff
                changed.insert(rule.id)
                Diag.log(.migration, "moved startMinutes to \(latestAllowedStartMinutes) minutes for rule-\(rule.id.logTag)")
            }
            
            if rule.endMinutes > rule.startMinutes,
               rule.endMinutes - rule.startMinutes < minimumRuleDurationMinutes {
                rule.endMinutes = rule.startMinutes + minimumRuleDurationMinutes
                
                if rule.endMinutes == 24 * 60 {
                    rule.endMinutes = 0
                }
                
                changed.insert(rule.id)
                Diag.log(.migration, "moved endMinutes to \(minimumRuleDurationMinutes) minutes after startMinutes for rule-\(rule.id.logTag)")
                
            }
            
            if rule.startMinutes % 5 != 0 {
                rule.startMinutes = rule.startMinutes - rule.startMinutes % 5
                changed.insert(rule.id)
                Diag.log(.migration, "clamped startMinutes for rule-\(rule.id.logTag)")
            }
            
            if rule.endMinutes % 5 != 0 {
                rule.endMinutes = rule.endMinutes - rule.endMinutes % 5
                changed.insert(rule.id)
                Diag.log(.migration, "clamped endMinutes for rule-\(rule.id.logTag)")
            }
        }
        
        try context.save()

        return changed
    }

    /// Copies each rule's legacy `appList` into the V3 `appLists` array, then
    /// strips the legacy column. Throws so a failed one-shot migration replays
    /// on next launch instead of dropping selections.
    static func promoteV2RuleAppLists(_ context: ModelContext) throws {
        let rules = try context.fetch(FetchDescriptor<BlockingRule>())
        var promoted = 0
        for rule in rules where rule.appLists.isEmpty && rule.appList != nil {
            rule.appLists = [rule.appList!]
            promoted += 1
        }
        for rule in rules where rule.appList != nil {
            rule.appList = nil
        }
        Diag.log(.migration, "promoted \(promoted) rules' legacy appList to appLists")
        try context.save()
    }
}
