//
//  URLResolver.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import Foundation

enum URLResolver {
    static func resolveRule(from url: URL, in rules: [BlockingRule]) -> BlockingRule? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard components.host == "rules" else {
            return nil
        }
        let ruleIdLookup = components.url?.lastPathComponent
        let matchingRule = rules.first { $0.id.uuidString == ruleIdLookup }
        return matchingRule
    }
}
