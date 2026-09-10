//
//  BlockingRule.swift
//  OpenAppLock
//

import Foundation
import SwiftData

// Set to the current schema version
typealias BlockingRule = OpenAppLockSchemaV2.BlockingRule

extension BlockingRule {
    /// The order rules appear in every list that shows them — the Rules tab's
    /// kind sections and the Home tab's "Currently Blocking" / "Active Rules"
    /// rows: alphabetical by name (localized, case-insensitive), with creation
    /// date breaking ties so rules sharing a name keep a stable order. Those
    /// views fetch with this via `@Query(sort:)`.
    ///
    /// Kept in an extension to mirror `AppList.displayOrder`, whose `@Model`-body
    /// placement demonstrably broke synthesized `Hashable` for a value type that
    /// holds it (`RuleDraft`). No value type relies on `BlockingRule`'s synthesized
    /// `Hashable` today, so here the extension is precautionary, not required.
    static let displayOrder: [SortDescriptor<BlockingRule>] = [
        SortDescriptor(\.name, comparator: .localizedStandard),
        SortDescriptor(\.createdAt),
    ]
}
