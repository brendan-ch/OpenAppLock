//
//  AppList.swift
//  OpenAppLock
//

import Foundation
import SwiftData

/// A named, reusable selection of apps/categories/websites. Rules point at a
/// list, so editing the list affects every rule that uses it. Deleting a list
/// detaches it from its rules (they fall back to "no apps").
@Model
final class AppList {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Encoded `FamilyActivitySelection` (opaque tokens). Nil until apps are picked.
    var selectionData: Data?
    /// Denormalized count of selected apps/categories/domains for display.
    var selectionCount: Int
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \BlockingRule.appList)
    var rules: [BlockingRule] = []

    init(
        id: UUID = UUID(),
        name: String,
        selectionData: Data? = nil,
        selectionCount: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.selectionData = selectionData
        self.selectionCount = selectionCount
        self.createdAt = createdAt
    }

    /// Whether any rule currently points at this list (guards deletion).
    static func isInUse(_ list: AppList, context: ModelContext) -> Bool {
        let listID = list.id
        let descriptor = FetchDescriptor<BlockingRule>(
            predicate: #Predicate { $0.appList?.id == listID }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// "4 Apps" / "1 App" label shared by the library, editor, and detail rows.
    var appCountLabel: String {
        selectionCount == 1 ? "1 App" : "\(selectionCount) Apps"
    }
    
    var ruleCountLabel: String {
        rules.count == 1 ? "1 Rule" : "\(rules.count) Rules"
    }
    
    var appAndRuleCountLabel: String {
        "\(appCountLabel) · \(ruleCountLabel)"
    }
}
