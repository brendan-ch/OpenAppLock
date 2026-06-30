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

extension AppList {
    /// The order app lists appear in the library — Settings ▸ App Lists and the
    /// rule editor's app-list picker: alphabetical by name (localized,
    /// case-insensitive), with creation date breaking ties so lists sharing a
    /// name keep a stable order. The library fetches with this via `@Query(sort:)`.
    ///
    /// Lives in an extension, not the `@Model` body: a self-referential
    /// `SortDescriptor<AppList>` static inside the macro-processed body breaks
    /// the model's synthesized `Hashable` conformance for value types that hold
    /// an `AppList` (e.g. `RuleDraft`).
    static let displayOrder: [SortDescriptor<AppList>] = [
        SortDescriptor(\.name, comparator: .localizedStandard),
        SortDescriptor(\.createdAt),
    ]
}
