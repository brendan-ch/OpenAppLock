//
//  URL+RuleID.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import Foundation

extension URL {
    nonisolated public static func fromRuleID(_ ruleID: UUID) -> URL? {
        return URL(string: "openapplock://rules/\(ruleID.uuidString)")
    }
}
