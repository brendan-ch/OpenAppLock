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
            let latestAllowedStartMinutes = 23 * 60 + 45
            let minimumRuleDurationMinutes = 15

            let rules = try context.fetch(FetchDescriptor<OpenAppLockSchemaV1.BlockingRule>())
            for rule in rules where rule.kind == .schedule {
                if rule.startMinutes > latestAllowedStartMinutes {
                    rule.startMinutes = latestAllowedStartMinutes
                }
                if rule.endMinutes > rule.startMinutes,
                   rule.endMinutes - rule.startMinutes < minimumRuleDurationMinutes {
                    rule.endMinutes = rule.startMinutes + minimumRuleDurationMinutes
                }
            }
            try context.save()
        }, didMigrate: nil
    )
}
