//
//  AppListMigration.swift
//  OpenAppLock
//

import Foundation
import SwiftData

/// One-time launch migration from the legacy model where every rule carried
/// its own inline `FamilyActivitySelection` to shared, reusable app lists.
///
/// Each rule that still has inline selection data gets a list named after it;
/// rules with byte-identical selections share a single list. The inline copy
/// is cleared afterwards, which also makes the migration idempotent.
enum AppListMigration {
    static func run(in context: ModelContext) {
        let descriptor = FetchDescriptor<BlockingRule>(
            predicate: #Predicate { $0.selectionData != nil }
        )
        guard let legacyRules = try? context.fetch(descriptor), !legacyRules.isEmpty else {
            return
        }

        var listsBySelection: [Data: AppList] = [:]
        for rule in legacyRules.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard rule.appList == nil, let selectionData = rule.selectionData else { continue }
            let list: AppList
            if let existing = listsBySelection[selectionData] {
                list = existing
            } else {
                list = AppList(
                    name: "\(rule.name) Apps",
                    selectionData: selectionData,
                    selectionCount: rule.selectionCount
                )
                context.insert(list)
                listsBySelection[selectionData] = list
            }
            rule.appList = list
            rule.selectionData = nil
            rule.selectionCount = 0
        }
        try? context.save()
    }
}
