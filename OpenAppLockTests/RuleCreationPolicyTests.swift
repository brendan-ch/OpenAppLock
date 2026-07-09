//
//  RuleCreationPolicyTests.swift
//  OpenAppLockTests
//

import Testing
@testable import OpenAppLock

@MainActor
struct RuleCreationPolicyTests {
    @Test func capIsTen() {
        #expect(RuleCreationPolicy.maxRuleCount == 10)
    }

    @Test func allowsCreationBelowTheCap() {
        #expect(RuleCreationPolicy.canCreateRule(existingRuleCount: 0))
        #expect(RuleCreationPolicy.canCreateRule(existingRuleCount: 9))
    }

    @Test func blocksCreationAtOrAboveTheCap() {
        #expect(!RuleCreationPolicy.canCreateRule(existingRuleCount: 10))
        #expect(!RuleCreationPolicy.canCreateRule(existingRuleCount: 11))
    }
}
