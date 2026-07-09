//
//  RuleCreationPolicy.swift
//  OpenAppLock
//

/// Whether a new rule may be created, given how many already exist.
///
/// A hard cap keeps the app within Apple's ~20 concurrent-DeviceActivity ceiling:
/// with N=1 time-limit arming (`RuleScheduler.dayActivityHorizon`) the worst case
/// is 2 activities per rule (a nudge-on time limit: one block + one warn), so
/// 10 rules → 20 activities. Counts ALL rules, enabled or not — a safe
/// over-approximation that needs no separate cap on enabling a rule.
enum RuleCreationPolicy {
    static let maxRuleCount = 10

    static func canCreateRule(existingRuleCount: Int) -> Bool {
        existingRuleCount < maxRuleCount
    }
}
