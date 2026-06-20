//
//  RuleEnforcerTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Rule enforcement → shields")
struct RuleEnforcerTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)
    let mondayEvening = date(2025, 1, 6, 19, 0)

    @Test("Active schedule rules are shielded; inactive ones are not")
    func shieldsActiveRules() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let active = BlockingRule(name: "Work Time")
        let weekendOnly = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)

        enforcer.refresh(rules: [active, weekendOnly], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs == [active.id])
        #expect(enforcer.blockingRuleIDs == [active.id])
    }

    @Test("Disabled rules are never shielded")
    func skipsDisabledRules() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time", isEnabled: false)

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Paused rules are not shielded")
    func skipsPausedRules() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")
        RulePolicy.unblock(rule, at: mondayDuringWork, calendar: utc)

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Time-limit rules are not schedule-shielded")
    func skipsTimeLimitRules() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig()))

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Shields are cleared when a window ends")
    func clearsShieldAfterWindow() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(shields.shieldedRuleIDs == [rule.id])

        enforcer.refresh(rules: [rule], at: mondayEvening, calendar: utc)
        #expect(shields.shieldedRuleIDs.isEmpty)
        #expect(enforcer.blockingRuleIDs.isEmpty)
    }

    @Test("Shields are cleared when a rule is deleted")
    func clearsShieldAfterDeletion() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        enforcer.refresh(rules: [], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("Expired pauses are cleaned up during refresh")
    func clearsExpiredPause() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(name: "Work Time")
        rule.pausedUntil = date(2025, 1, 6, 9, 30)

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(rule.pausedUntil == nil)
        #expect(shields.shieldedRuleIDs == [rule.id])
    }

    @Test("The selection mode is forwarded to the shield layer")
    func forwardsSelectionMode() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let rule = BlockingRule(
            name: "Focus", configuration: .schedule(ScheduleConfig(selectionMode: .allowOnly)))

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.appliedModes[rule.id] == .allowOnly)
    }

    @Test("Open-limit rules are proactively shielded while opens remain")
    func proactivelyShieldsOpenLimit() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
            days: Weekday.everyDay)
        // 2 of 5 opens spent: budget not reached, so the rule is not "active",
        // but its apps must still be gated so the next open can be counted.
        ledger.usageByRule[rule.id] = RuleUsage(opensUsed: 2)

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs == [rule.id])
        #expect(shields.appliedModes[rule.id] == .block)
        // A proactive gate (opens remaining) is not "Blocked Apps"-blocking.
        #expect(enforcer.blockingRuleIDs.isEmpty)
    }

    @Test("A granted open session is left un-shielded, not re-locked")
    func respectsGrantedOpenSession() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let sessions = MockOpenSessionStore()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger, openSessions: sessions)
        let rule = BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
            days: Weekday.everyDay)
        ledger.usageByRule[rule.id] = RuleUsage(opensUsed: 2)
        // The user spent an open and is mid-session; re-shielding would cut the
        // sanctioned ~15-minute session short.
        sessions.activeRuleIDs = [rule.id]

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("The adult-content flag is forwarded to the shield layer")
    func forwardsAdultContentFlag() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields)
        let filtered = BlockingRule(
            name: "Clean Mode", configuration: .schedule(ScheduleConfig(blockAdultContent: true)))
        let unfiltered = BlockingRule(name: "Plain")

        enforcer.refresh(rules: [filtered, unfiltered], at: mondayDuringWork, calendar: utc)

        #expect(shields.appliedAdultContentFlags[filtered.id] == true)
        #expect(shields.appliedAdultContentFlags[unfiltered.id] == false)
    }
}

/// Validates the "strictest enforcement wins" model for rules that target the
/// same apps (see `RuleEnforcer`). Each rule shields its own store and Screen
/// Time unions them, so the unit-level invariant is: every rule that should
/// block applies its own shield, and no rule's shield is suppressed by another.
@MainActor
@Suite("Overlapping rules → strictest enforcement")
struct OverlappingRuleEnforcementTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)

    private func openLimitRule(maxOpens: Int = 5) -> BlockingRule {
        BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: maxOpens)),
            days: Weekday.everyDay)
    }

    private func timeLimitRule(limit: Int = 45) -> BlockingRule {
        BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: limit)),
            days: Weekday.everyDay)
    }

    @Test("Every rule that should block applies its own shield")
    func eachRuleShieldsIndependently() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let schedule = BlockingRule(name: "Work Time")  // 09:00–17:00, active now
        let timeLimit = timeLimitRule()
        ledger.usageByRule[timeLimit.id] = RuleUsage(minutesUsed: 45)  // spent → blocking

        enforcer.refresh(rules: [schedule, timeLimit], at: mondayDuringWork, calendar: utc)

        // Neither cancels the other: both carry their own shield.
        #expect(shields.shieldedRuleIDs == [schedule.id, timeLimit.id])
    }

    @Test("The first limit to be spent blocks, whatever the other's budget")
    func firstSpentLimitBlocks() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let openLimit = openLimitRule(maxOpens: 5)
        let timeLimit = timeLimitRule(limit: 45)
        ledger.usageByRule[openLimit.id] = RuleUsage(opensUsed: 1)    // opens remain
        ledger.usageByRule[timeLimit.id] = RuleUsage(minutesUsed: 45)  // budget spent

        enforcer.refresh(rules: [openLimit, timeLimit], at: mondayDuringWork, calendar: utc)

        // Time-limit blocks (spent) while the open-limit still gates its turnstile.
        #expect(shields.shieldedRuleIDs == [openLimit.id, timeLimit.id])
        // Only the spent budget counts as "Blocked Apps"; the gate shows in Usage.
        #expect(enforcer.blockingRuleIDs == [timeLimit.id])
    }

    @Test("A time limit blocks even during an open-limit's granted session")
    func timeLimitBlocksDuringGrantedOpen() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let sessions = MockOpenSessionStore()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger, openSessions: sessions)
        let openLimit = openLimitRule(maxOpens: 5)
        let timeLimit = timeLimitRule(limit: 45)
        sessions.activeRuleIDs = [openLimit.id]  // user is mid-open on the shared app
        ledger.usageByRule[openLimit.id] = RuleUsage(opensUsed: 1)
        // The metered minutes during the open push the time limit over budget.
        ledger.usageByRule[timeLimit.id] = RuleUsage(minutesUsed: 45)

        enforcer.refresh(rules: [openLimit, timeLimit], at: mondayDuringWork, calendar: utc)

        // The open-limit stays lifted (its session is sanctioned), but the time
        // limit shields the app anyway — strictest wins.
        #expect(shields.shieldedRuleIDs == [timeLimit.id])
    }

    @Test("Spent opens reset the next day: re-gated, not blocked")
    func opensResetNextDay() {
        let suite = "overlap-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let ledger = UsageLedger(defaults: defaults)
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = openLimitRule(maxOpens: 5)
        let yesterday = date(2025, 1, 5, 10, 0)
        let today = date(2025, 1, 6, 10, 0)
        for _ in 0..<5 {
            ledger.recordOpen(for: rule.id, onDayContaining: yesterday, calendar: utc)
        }

        // Yesterday: budget exhausted → blocking.
        enforcer.refresh(rules: [rule], at: yesterday, calendar: utc)
        #expect(enforcer.blockingRuleIDs == [rule.id])

        // Today: fresh budget → not blocking, but the turnstile is back up.
        enforcer.refresh(rules: [rule], at: today, calendar: utc)
        #expect(enforcer.blockingRuleIDs.isEmpty)
        #expect(shields.shieldedRuleIDs == [rule.id])
    }
}

/// Uninstall Protection: `refresh` denies device app removal only while the
/// user opted in *and* a Hard Mode rule is actively blocking.
@MainActor
@Suite("Uninstall protection enforcement")
struct UninstallProtectionEnforcementTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)  // inside the default 09:00–17:00
    let mondayEvening = date(2025, 1, 6, 19, 0)     // outside it

    private func hardRule() -> BlockingRule {
        BlockingRule(name: "Locked In", hardMode: true)
    }

    @Test("Disabled setting never denies app removal")
    func disabledSettingNeverDenies() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(
            shields: shields, settings: MockAppSettings(uninstallProtectionEnabled: false))

        enforcer.refresh(rules: [hardRule()], at: mondayDuringWork, calendar: utc)

        #expect(!shields.appRemovalDenied)
    }

    @Test("Enabled setting denies removal while a hard rule is blocking")
    func deniesDuringHardBlock() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(
            shields: shields, settings: MockAppSettings(uninstallProtectionEnabled: true))

        enforcer.refresh(rules: [hardRule()], at: mondayDuringWork, calendar: utc)

        #expect(shields.appRemovalDenied)
    }

    @Test("A soft rule does not deny removal even with the setting on")
    func softRuleDoesNotDeny() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(
            shields: shields, settings: MockAppSettings(uninstallProtectionEnabled: true))

        enforcer.refresh(rules: [BlockingRule(name: "Work Time")], at: mondayDuringWork, calendar: utc)

        #expect(!shields.appRemovalDenied)
    }

    @Test("Denial lifts once the hard window ends")
    func liftsWhenWindowEnds() {
        let shields = MockShieldController()
        let enforcer = RuleEnforcer(
            shields: shields, settings: MockAppSettings(uninstallProtectionEnabled: true))
        let rule = hardRule()

        enforcer.refresh(rules: [rule], at: mondayDuringWork, calendar: utc)
        #expect(shields.appRemovalDenied)

        enforcer.refresh(rules: [rule], at: mondayEvening, calendar: utc)
        #expect(!shields.appRemovalDenied)
    }

    @Test("clearShields(except:) does not disturb the app-removal denial")
    func clearShieldsPreservesDenial() {
        let shields = MockShieldController()
        shields.setAppRemovalDenied(true)
        shields.clearShields(except: [])
        #expect(shields.appRemovalDenied)
    }
}
