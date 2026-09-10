//
//  OpenAppLockSchemaMigrationPlan.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.09.
//

import SwiftData

enum OpenAppLockSchemaMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    static var schemas: [any VersionedSchema.Type] = [
        OpenAppLockSchemaV1.self,
        OpenAppLockSchemaV2.self
    ]
    
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: OpenAppLockSchemaV1.self,
        toVersion: OpenAppLockSchemaV2.self,
        willMigrate: { context in
            Diag.log(.migration, "migrating schema from V1 to V2")
            let latestAllowedStartMinutes = 23 * 60 + 45
            let minimumRuleDurationMinutes = 15

            let rules = try context.fetch(FetchDescriptor<OpenAppLockSchemaV1.BlockingRule>())
            for rule in rules where rule.kind == .schedule {
                if rule.startMinutes % 5 != 0 {
                    rule.startMinutes = rule.startMinutes - rule.startMinutes % 5
                    Diag.log(.migration, "clamped startMinutes for rule-\(rule.id.logTag)")
                }
                if rule.endMinutes % 5 != 0 {
                    rule.endMinutes = rule.endMinutes - rule.endMinutes % 5
                    Diag.log(.migration, "clamped endMinutes for rule-\(rule.id.logTag)")
                }
                if rule.startMinutes > latestAllowedStartMinutes {
                    rule.startMinutes = latestAllowedStartMinutes
                    Diag.log(.migration, "moved startMinutes to \(latestAllowedStartMinutes) minutes for rule-\(rule.id.logTag)")
                }
                if rule.endMinutes > rule.startMinutes,
                   rule.endMinutes - rule.startMinutes < minimumRuleDurationMinutes {
                    rule.endMinutes = rule.startMinutes + minimumRuleDurationMinutes
                    Diag.log(.migration, "moved endMinutes to \(minimumRuleDurationMinutes) minutes after startMinutes for rule-\(rule.id.logTag)")
                }
            }
            try context.save()
        }, didMigrate: nil
    )
}
