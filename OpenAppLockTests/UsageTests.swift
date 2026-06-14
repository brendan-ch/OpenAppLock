//
//  UsageTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Usage ledger")
struct UsageLedgerTests {
    private func makeLedger() -> UsageLedger {
        let suiteName = "usage-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UsageLedger(defaults: defaults)
    }

    let monday = date(2025, 1, 6, 10, 0)
    let tuesday = date(2025, 1, 7, 10, 0)

    @Test("Day keys are calendar dates")
    func dayKey() {
        #expect(UsageLedger.dayKey(for: monday, calendar: utc) == "2025-01-06")
        #expect(UsageLedger.dayKey(for: date(2025, 12, 31, 23, 59), calendar: utc) == "2025-12-31")
    }

    @Test("Usage defaults to zero and round-trips")
    func roundTrip() {
        let ledger = makeLedger()
        let ruleID = UUID()
        #expect(ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc) == RuleUsage())

        ledger.setUsage(
            RuleUsage(minutesUsed: 12, opensUsed: 3),
            for: ruleID, onDayContaining: monday, calendar: utc
        )
        let read = ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc)
        #expect(read.minutesUsed == 12)
        #expect(read.opensUsed == 3)
    }

    @Test("Recorded minutes are monotonic per day")
    func monotonicMinutes() {
        let ledger = makeLedger()
        let ruleID = UUID()
        ledger.recordMinutesUsed(10, for: ruleID, onDayContaining: monday, calendar: utc)
        ledger.recordMinutesUsed(7, for: ruleID, onDayContaining: monday, calendar: utc)
        #expect(ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc).minutesUsed == 10)
        ledger.recordMinutesUsed(25, for: ruleID, onDayContaining: monday, calendar: utc)
        #expect(ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc).minutesUsed == 25)
    }

    @Test("Opens increment per day")
    func opensIncrement() {
        let ledger = makeLedger()
        let ruleID = UUID()
        ledger.recordOpen(for: ruleID, onDayContaining: monday, calendar: utc)
        ledger.recordOpen(for: ruleID, onDayContaining: monday, calendar: utc)
        #expect(ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc).opensUsed == 2)
    }

    @Test("Usage is separated by day and rule")
    func separation() {
        let ledger = makeLedger()
        let first = UUID()
        let second = UUID()
        ledger.recordMinutesUsed(30, for: first, onDayContaining: monday, calendar: utc)
        #expect(ledger.usage(for: first, onDayContaining: tuesday, calendar: utc) == RuleUsage())
        #expect(ledger.usage(for: second, onDayContaining: monday, calendar: utc) == RuleUsage())
    }
}

@MainActor
@Suite("Usage-aware rule status")
struct UsageStatusTests {
    let mondayMorning = date(2025, 1, 6, 10, 0)

    private func timeLimitRule(limit: Int = 45) -> BlockingRule {
        BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: limit)),
            days: Weekday.everyDay)
    }

    private func openLimitRule(maxOpens: Int = 5) -> BlockingRule {
        BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: maxOpens)),
            days: Weekday.everyDay)
    }

    @Test("A time-limit rule with budget left is not active")
    func budgetLeftNotActive() {
        let rule = timeLimitRule()
        let status = rule.status(at: mondayMorning, calendar: utc, usage: RuleUsage(minutesUsed: 20))
        #expect(!status.isActive)
    }

    @Test("A time-limit rule blocks until midnight once its budget is spent")
    func spentBudgetBlocksUntilMidnight() {
        let rule = timeLimitRule(limit: 45)
        let status = rule.status(at: mondayMorning, calendar: utc, usage: RuleUsage(minutesUsed: 45))
        #expect(status == .active(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("An open-limit rule blocks once opens are exhausted")
    func exhaustedOpensBlock() {
        let rule = openLimitRule(maxOpens: 5)
        let status = rule.status(at: mondayMorning, calendar: utc, usage: RuleUsage(opensUsed: 5))
        #expect(status == .active(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("A spent budget on a disabled day does not block")
    func disabledDayDoesNotBlock() {
        let rule = timeLimitRule()
        rule.days = Weekday.weekends
        let status = rule.status(at: mondayMorning, calendar: utc, usage: RuleUsage(minutesUsed: 99))
        #expect(!status.isActive)
    }

    @Test("Unblocking a limit-blocked rule pauses it until midnight")
    func unblockPausesUntilMidnight() {
        let rule = timeLimitRule(limit: 45)
        let usage = RuleUsage(minutesUsed: 45)
        #expect(RulePolicy.canUnblock(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(RulePolicy.unblock(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(rule.pausedUntil == date(2025, 1, 7, 0, 0))
        #expect(
            rule.status(at: mondayMorning, calendar: utc, usage: usage)
                == .paused(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("Hard Mode locks a limit-blocked rule and its app lists")
    func hardModeLocksLimitBlock() {
        let rule = timeLimitRule(limit: 45)
        rule.hardMode = true
        let usage = RuleUsage(minutesUsed: 45)
        #expect(RulePolicy.isHardLocked(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(!RulePolicy.canUnblock(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(
            !RulePolicy.canEditAppLists(
                rules: [rule], usageFor: { _ in usage }, at: mondayMorning, calendar: utc))
    }
}

@MainActor
@Suite("Enforcement of limit rules")
struct UsageEnforcementTests {
    let mondayMorning = date(2025, 1, 6, 10, 0)

    @Test("A spent time-limit rule is shielded in Block mode")
    func shieldsSpentTimeLimit() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        ledger.usageByRule[rule.id] = RuleUsage(minutesUsed: 45)

        enforcer.refresh(rules: [rule], at: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs == [rule.id])
        #expect(shields.appliedModes[rule.id] == .block)
        // Limit rules never engage the adult-content filter (Schedule-only).
        #expect(shields.appliedAdultContentFlags[rule.id] == false)
    }

    @Test("A time-limit rule with budget left is not shielded")
    func leavesUnspentTimeLimitAlone() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        ledger.usageByRule[rule.id] = RuleUsage(minutesUsed: 20)

        enforcer.refresh(rules: [rule], at: mondayMorning, calendar: utc)

        // Time limits let the OS meter usage on the unshielded app, so nothing
        // is shielded until the budget is spent. (Open limits differ — the
        // shield is the meter, so they are gated proactively; see
        // RuleEnforcerTests.proactivelyShieldsOpenLimit.)
        #expect(shields.shieldedRuleIDs.isEmpty)
    }

    @Test("An open-limit rule not scheduled today is not gated")
    func leavesOffDayOpenLimitAlone() {
        let shields = MockShieldController()
        let ledger = MockUsageLedger()
        let enforcer = RuleEnforcer(shields: shields, usage: ledger)
        let rule = BlockingRule(
            name: "Gate Keeper",
            configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
            days: Weekday.weekends)
        ledger.usageByRule[rule.id] = RuleUsage(opensUsed: 2)

        // mondayMorning is a weekday, so the weekend-only rule does not gate.
        enforcer.refresh(rules: [rule], at: mondayMorning, calendar: utc)

        #expect(shields.shieldedRuleIDs.isEmpty)
    }
}

@MainActor
@Suite("Usage display strings")
struct UsageDisplayTests {
    let timeRule = BlockingRule(
        name: "Time Keeper",
        configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
        days: Weekday.everyDay)
    let openRule = BlockingRule(
        name: "Gate Keeper",
        configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
        days: Weekday.everyDay)

    @Test("Time-limit rows show minutes used and remaining")
    func timeLimitStrings() {
        let usage = RuleUsage(minutesUsed: 18)
        #expect(UsageDisplay.subtitle(for: timeRule, usage: usage) == "18m of 45m used today")
        #expect(UsageDisplay.remainingLabel(for: timeRule, usage: usage, isPaused: false) == "27m left")
    }

    @Test("Open-limit rows show opens used and remaining")
    func openLimitStrings() {
        let usage = RuleUsage(opensUsed: 2)
        #expect(UsageDisplay.subtitle(for: openRule, usage: usage) == "2 of 5 opens today")
        #expect(UsageDisplay.remainingLabel(for: openRule, usage: usage, isPaused: false) == "3 opens left")

        let oneLeft = RuleUsage(opensUsed: 4)
        #expect(UsageDisplay.remainingLabel(for: openRule, usage: oneLeft, isPaused: false) == "1 open left")
    }

    @Test("Spent budgets read as blocked, or unblocked while paused")
    func exhaustedStrings() {
        let spent = RuleUsage(minutesUsed: 45)
        #expect(
            UsageDisplay.remainingLabel(for: timeRule, usage: spent, isPaused: false)
                == "Blocked until tomorrow")
        #expect(
            UsageDisplay.remainingLabel(for: timeRule, usage: spent, isPaused: true)
                == "Unblocked until tomorrow")
        #expect(UsageDisplay.subtitle(for: timeRule, usage: spent) == "45m of 45m used today")
    }

    @Test("Overshoot clamps to the budget")
    func overshootClamps() {
        let over = RuleUsage(minutesUsed: 60)
        #expect(UsageDisplay.subtitle(for: timeRule, usage: over) == "45m of 45m used today")
    }

    @Test("Typed subtitles prefix the rule kind so type is clear without the icon")
    func typedSubtitles() {
        #expect(
            UsageDisplay.typedSubtitle(for: timeRule, usage: RuleUsage(minutesUsed: 18))
                == "Time Limit · 18m of 45m used today")
        #expect(
            UsageDisplay.typedSubtitle(for: openRule, usage: RuleUsage(opensUsed: 2))
                == "Open Limit · 2 of 5 opens today")
    }
}
