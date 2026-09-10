//
//  AppList.swift
//  OpenAppLock
//

import Foundation
import SwiftData

// Set to the current schema version
typealias AppList = OpenAppLockSchemaV2.AppList

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
