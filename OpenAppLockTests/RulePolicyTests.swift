//
//  RulePolicyTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Hard Mode policy")
struct RulePolicyTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    func rule(hardMode: Bool) -> BlockingRule {
        BlockingRule(name: "Work Time", hardMode: hardMode)
    }

    @Test("An active Hard Mode rule is locked")
    func hardLockedWhileActive() {
        let rule = rule(hardMode: true)
        #expect(RulePolicy.isHardLocked(rule, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canEdit(rule, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canDisable(rule, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canDelete(rule, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canUnblock(rule, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canTurnOffHardMode(rule, at: mondayDuringWork, calendar: utc))
    }

    @Test("A Hard Mode rule unlocks once its window ends")
    func unlockedOutsideWindow() {
        let rule = rule(hardMode: true)
        #expect(!RulePolicy.isHardLocked(rule, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canEdit(rule, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canDisable(rule, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canDelete(rule, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canTurnOffHardMode(rule, at: mondayEvening, calendar: utc))
    }

    @Test("A disabled Hard Mode rule is not locked")
    func disabledRuleNotLocked() {
        let rule = rule(hardMode: true)
        rule.isEnabled = false
        #expect(!RulePolicy.isHardLocked(rule, at: mondayDuringWork, calendar: utc))
        #expect(RulePolicy.canEdit(rule, at: mondayDuringWork, calendar: utc))
    }

    @Test("Active non-Hard-Mode rules may be unblocked")
    func softRuleUnblockable() {
        let rule = rule(hardMode: false)
        #expect(RulePolicy.canUnblock(rule, at: mondayDuringWork, calendar: utc))
    }

    @Test("Unblocking pauses the rule until its window ends")
    func unblockPausesUntilWindowEnd() {
        let rule = rule(hardMode: false)
        let didUnblock = RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)
        #expect(didUnblock)
        #expect(rule.pausedUntil == date(2025, 1, 6, 17, 0))
        #expect(rule.status(at: mondayDuringWork, calendar: utc)
            == .paused(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Unblocking a Hard Mode rule is refused and changes nothing")
    func hardModeUnblockRefused() {
        let rule = rule(hardMode: true)
        let didUnblock = RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)
        #expect(!didUnblock)
        #expect(rule.pausedUntil == nil)
        #expect(rule.status(at: mondayDuringWork, calendar: utc).isActive)
    }

    @Test("Unblocking an inactive rule is refused")
    func inactiveUnblockRefused() {
        let rule = rule(hardMode: false)
        #expect(!RulePolicy.unblock(rule, at: mondayEvening, calendar: utc))
        #expect(rule.pausedUntil == nil)
    }
}

@MainActor
@Suite("Uninstall protection policy")
struct UninstallProtectionPolicyTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    func scheduleRule(hardMode: Bool) -> BlockingRule {
        BlockingRule(name: "Work Time", hardMode: hardMode)
    }

    func hardLimitRule() -> BlockingRule {
        BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            hardMode: true,
            days: Weekday.everyDay)
    }

    @Test("App removal is only denied with the setting on AND a hard rule active")
    func deniedOnlyWhenEnabledAndHardLocked() {
        let hard = scheduleRule(hardMode: true)
        // Setting off: never deny, even with an active hard rule.
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                rules: [hard], enabled: false, at: mondayDuringWork, calendar: utc))
        // Setting on + active hard rule: deny.
        #expect(
            RulePolicy.shouldDenyAppRemoval(
                rules: [hard], enabled: true, at: mondayDuringWork, calendar: utc))
        // Setting on but the hard rule is outside its window: do not deny.
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                rules: [hard], enabled: true, at: mondayEvening, calendar: utc))
    }

    @Test("A soft rule never triggers app-removal denial")
    func softRuleNeverDenies() {
        let soft = scheduleRule(hardMode: false)
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                rules: [soft], enabled: true, at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent hard-mode limit rule triggers denial; unspent does not")
    func spentHardLimitDenies() {
        let rule = hardLimitRule()
        #expect(
            RulePolicy.shouldDenyAppRemoval(
                rules: [rule], enabled: true, usageFor: { _ in RuleUsage(minutesUsed: 45) },
                at: mondayDuringWork, calendar: utc))
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                rules: [rule], enabled: true, usageFor: { _ in RuleUsage(minutesUsed: 10) },
                at: mondayDuringWork, calendar: utc))
    }
}
