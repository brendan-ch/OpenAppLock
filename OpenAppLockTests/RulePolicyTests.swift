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
        #expect(RulePolicy.isHardLocked(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canEdit(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canDisable(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canDelete(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canUnblock(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(!RulePolicy.canTurnOffHardMode(rule.dto, at: mondayDuringWork, calendar: utc))
    }

    @Test("A Hard Mode rule unlocks once its window ends")
    func unlockedOutsideWindow() {
        let rule = rule(hardMode: true)
        #expect(!RulePolicy.isHardLocked(rule.dto, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canEdit(rule.dto, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canDisable(rule.dto, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canDelete(rule.dto, at: mondayEvening, calendar: utc))
        #expect(RulePolicy.canTurnOffHardMode(rule.dto, at: mondayEvening, calendar: utc))
    }

    @Test("A disabled Hard Mode rule is not locked")
    func disabledRuleNotLocked() {
        let rule = rule(hardMode: true)
        rule.isEnabled = false
        #expect(!RulePolicy.isHardLocked(rule.dto, at: mondayDuringWork, calendar: utc))
        #expect(RulePolicy.canEdit(rule.dto, at: mondayDuringWork, calendar: utc))
    }

    @Test("Active non-Hard-Mode rules may be unblocked")
    func softRuleUnblockable() {
        let rule = rule(hardMode: false)
        #expect(RulePolicy.canUnblock(rule.dto, at: mondayDuringWork, calendar: utc))
    }

    @Test("Unblocking pauses the rule until its window ends")
    func unblockPausesUntilWindowEnd() {
        let rule = rule(hardMode: false)
        let didUnblock = RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)
        #expect(didUnblock)
        #expect(rule.pausedUntil == date(2025, 1, 6, 17, 0))
        #expect(rule.dto.status(at: mondayDuringWork, calendar: utc)
            == .paused(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Unblocking a Hard Mode rule is refused and changes nothing")
    func hardModeUnblockRefused() {
        let rule = rule(hardMode: true)
        let didUnblock = RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)
        #expect(!didUnblock)
        #expect(rule.pausedUntil == nil)
        #expect(rule.dto.status(at: mondayDuringWork, calendar: utc).isActive)
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
                snapshots: [hard].map(\.dto), enabled: false, at: mondayDuringWork, calendar: utc))
        // Setting on + active hard rule: deny.
        #expect(
            RulePolicy.shouldDenyAppRemoval(
                snapshots: [hard].map(\.dto), enabled: true, at: mondayDuringWork, calendar: utc))
        // Setting on but the hard rule is outside its window: do not deny.
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                snapshots: [hard].map(\.dto), enabled: true, at: mondayEvening, calendar: utc))
    }

    @Test("A soft rule never triggers app-removal denial")
    func softRuleNeverDenies() {
        let soft = scheduleRule(hardMode: false)
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                snapshots: [soft].map(\.dto), enabled: true, at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent hard-mode limit rule triggers denial; unspent does not")
    func spentHardLimitDenies() {
        let rule = hardLimitRule()
        #expect(
            RulePolicy.shouldDenyAppRemoval(
                snapshots: [rule].map(\.dto), enabled: true, usageFor: { _ in RuleUsageDTO(minutesUsed: 45) },
                at: mondayDuringWork, calendar: utc))
        #expect(
            !RulePolicy.shouldDenyAppRemoval(
                snapshots: [rule].map(\.dto), enabled: true, usageFor: { _ in RuleUsageDTO(minutesUsed: 10) },
                at: mondayDuringWork, calendar: utc))
    }

    @Test("The toggle is locked while a hard rule is actively blocking")
    func toggleLockedDuringHardBlock() {
        let hard = scheduleRule(hardMode: true)
        // Actively blocking → locked.
        #expect(
            !RulePolicy.canToggleUninstallProtection(
                snapshots: [hard].map(\.dto), at: mondayDuringWork, calendar: utc))
        // Outside its window → editable again.
        #expect(
            RulePolicy.canToggleUninstallProtection(
                snapshots: [hard].map(\.dto), at: mondayEvening, calendar: utc))
    }

    @Test("The toggle stays editable when only a soft rule is blocking")
    func toggleEditableWithSoftRule() {
        let soft = scheduleRule(hardMode: false)
        #expect(
            RulePolicy.canToggleUninstallProtection(
                snapshots: [soft].map(\.dto), at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent hard-mode limit rule locks the toggle")
    func toggleLockedByHardLimit() {
        let rule = hardLimitRule()
        #expect(
            !RulePolicy.canToggleUninstallProtection(
                snapshots: [rule].map(\.dto), usageFor: { _ in RuleUsageDTO(minutesUsed: 45) },
                at: mondayDuringWork, calendar: utc))
        #expect(
            RulePolicy.canToggleUninstallProtection(
                snapshots: [rule].map(\.dto), usageFor: { _ in RuleUsageDTO(minutesUsed: 10) },
                at: mondayDuringWork, calendar: utc))
    }
}

/// The snapshot-based uninstall-protection policy used by the background
/// (extension) enforcement path. Both this and `RulePolicy` now derive their
/// "actively blocking" judgement from the single `RuleActivation` primitive, so
/// they cannot drift — no parity test is needed.
@MainActor
@Suite("Uninstall protection policy (snapshot)")
struct UninstallProtectionSnapshotPolicyTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)  // inside the default 09:00–17:00
    let mondayEvening = date(2025, 1, 6, 19, 0)      // outside it

    func scheduleRule(hardMode: Bool) -> BlockingRule {
        BlockingRule(name: "Work Time", hardMode: hardMode)
    }

    /// A hard time-limit blocking every day, so it is scheduled on the Monday
    /// the test dates fall on.
    func hardLimitRule() -> BlockingRule {
        BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            hardMode: true,
            days: Weekday.everyDay)
    }

    /// A hard time-limit scheduled only on Tuesdays — never active on the test
    /// Mondays even when its budget is spent.
    func tuesdayHardLimitRule() -> BlockingRule {
        BlockingRule(
            name: "Tuesday Only",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            hardMode: true,
            days: [.tuesday])
    }

    @Test("App removal denied only with the setting on AND a hard snapshot active")
    func deniedOnlyWhenEnabledAndHardLocked() {
        let snap = RuleSnapshotDTO(rule: scheduleRule(hardMode: true))
        #expect(
            !UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: false, at: mondayDuringWork, calendar: utc))
        #expect(
            UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, at: mondayDuringWork, calendar: utc))
        #expect(
            !UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, at: mondayEvening, calendar: utc))
    }

    @Test("A soft snapshot never triggers denial")
    func softRuleNeverDenies() {
        let snap = RuleSnapshotDTO(rule: scheduleRule(hardMode: false))
        #expect(
            !UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent hard-mode limit snapshot denies; unspent does not")
    func spentHardLimitDenies() {
        let snap = RuleSnapshotDTO(rule: hardLimitRule())
        #expect(
            UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, usageFor: { _ in RuleUsageDTO(minutesUsed: 45) },
                at: mondayDuringWork, calendar: utc))
        #expect(
            !UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, usageFor: { _ in RuleUsageDTO(minutesUsed: 10) },
                at: mondayDuringWork, calendar: utc))
    }

    @Test("A spent hard limit not scheduled today does not deny")
    func spentButNotScheduledTodayDoesNotDeny() {
        // Guards the WIP bug: omitting the scheduled-today check would wrongly
        // deny removal for a Tuesday-only rule on a Monday.
        let snap = RuleSnapshotDTO(rule: tuesdayHardLimitRule())
        #expect(
            !UninstallProtectionPolicy.shouldDenyAppRemoval(
                snapshots: [snap], enabled: true, usageFor: { _ in RuleUsageDTO(minutesUsed: 99) },
                at: mondayDuringWork, calendar: utc))
    }
}
