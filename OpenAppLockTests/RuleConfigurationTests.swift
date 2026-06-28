//
//  RuleConfigurationTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("RuleConfiguration sum type")
struct RuleConfigurationTests {
    @Test("Each case reports its kind")
    func kindDerivation() {
        #expect(RuleConfiguration.schedule(ScheduleConfig()).kind == .schedule)
        #expect(RuleConfiguration.timeLimit(TimeLimitConfig()).kind == .timeLimit)
        #expect(RuleConfiguration.openLimit(OpenLimitConfig()).kind == .openLimit)
    }

    @Test("Defaults match the documented new-rule defaults")
    func defaults() {
        let schedule = RuleConfiguration.default(for: .schedule).scheduleConfig
        #expect(schedule?.startMinutes == 9 * 60)
        #expect(schedule?.endMinutes == 17 * 60)
        #expect(schedule?.selectionMode == .block)

        #expect(RuleConfiguration.default(for: .timeLimit).timeLimitConfig?.dailyLimitMinutes == 45)
        #expect(RuleConfiguration.default(for: .openLimit).openLimitConfig?.maxOpens == 5)
    }

    @Test("Typed projections only unwrap the matching case")
    func projections() {
        let schedule = RuleConfiguration.schedule(ScheduleConfig(selectionMode: .allowOnly))
        #expect(schedule.scheduleConfig?.selectionMode == .allowOnly)
        #expect(schedule.timeLimitConfig == nil)
        #expect(schedule.openLimitConfig == nil)

        let openLimit = RuleConfiguration.openLimit(OpenLimitConfig(maxOpens: 7))
        #expect(openLimit.openLimitConfig?.maxOpens == 7)
        #expect(openLimit.scheduleConfig == nil)
    }
}
