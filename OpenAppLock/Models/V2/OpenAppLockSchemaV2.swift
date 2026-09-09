//
//  OpenAppLockSchemaV2.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.09.
//

import SwiftData

struct OpenAppLockSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        return [BlockingRule.self, AppList.self]
    }
}
