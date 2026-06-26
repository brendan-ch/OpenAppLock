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
        #expect(ledger.usage(for: ruleID, onDayContaining: monday, calendar: utc) == RuleUsageDTO())

        ledger.setUsage(
            RuleUsageDTO(minutesUsed: 12, opensUsed: 3),
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
        #expect(ledger.usage(for: first, onDayContaining: tuesday, calendar: utc) == RuleUsageDTO())
        #expect(ledger.usage(for: second, onDayContaining: monday, calendar: utc) == RuleUsageDTO())
    }

    @Test("Effective minutes prefer a fresh authoritative reading, else fall back")
    func effectiveMinutes() {
        let now = date(2025, 1, 6, 10, 0)
        var usage = RuleUsageDTO(minutesUsed: 12)
        // No authoritative reading → threshold count.
        #expect(usage.effectiveMinutesUsed(asOf: now) == 12)
        // Fresh authoritative → wins.
        usage.authoritativeMinutesUsed = 20
        usage.authoritativeAsOf = now.addingTimeInterval(-30)
        #expect(usage.effectiveMinutesUsed(asOf: now) == 20)
        // Stale authoritative → threshold fallback.
        usage.authoritativeAsOf = now.addingTimeInterval(-600)
        #expect(usage.effectiveMinutesUsed(asOf: now) == 12)
    }

    @Test("Usage round-trips authoritative fields and decodes legacy blobs")
    func authoritativeCodable() throws {
        var usage = RuleUsageDTO(minutesUsed: 5, opensUsed: 2)
        usage.authoritativeMinutesUsed = 30
        usage.authoritativeAsOf = date(2025, 1, 6, 10, 0)
        let data = try JSONEncoder().encode(usage)
        #expect(try JSONDecoder().decode(RuleUsageDTO.self, from: data) == usage)

        // A blob written before the authoritative fields existed still decodes.
        let legacy = Data(#"{"minutesUsed":7,"opensUsed":1}"#.utf8)
        let decoded = try JSONDecoder().decode(RuleUsageDTO.self, from: legacy)
        #expect(decoded.minutesUsed == 7)
        #expect(decoded.authoritativeMinutesUsed == nil)
        #expect(decoded.authoritativeAsOf == nil)
    }

    @Test("Authoritative minutes overwrite without disturbing the threshold count")
    func recordAuthoritative() {
        let ledger = makeLedger()
        let id = UUID()
        ledger.recordMinutesUsed(40, for: id, onDayContaining: monday, calendar: utc)

        ledger.recordAuthoritativeMinutes(
            12, for: id, onDayContaining: monday, asOf: monday, calendar: utc)
        let read = ledger.usage(for: id, onDayContaining: monday, calendar: utc)
        #expect(read.minutesUsed == 40)               // threshold untouched
        #expect(read.authoritativeMinutesUsed == 12)  // authoritative recorded
        #expect(read.authoritativeAsOf == monday)
        // Effective prefers the (fresh) authoritative figure.
        #expect(read.effectiveMinutesUsed(asOf: monday) == 12)
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
        let status = rule.dto.status(at: mondayMorning, calendar: utc, usage: RuleUsageDTO(minutesUsed: 20))
        #expect(!status.isActive)
    }

    @Test("A time-limit rule blocks until midnight once its budget is spent")
    func spentBudgetBlocksUntilMidnight() {
        let rule = timeLimitRule(limit: 45)
        let status = rule.dto.status(at: mondayMorning, calendar: utc, usage: RuleUsageDTO(minutesUsed: 45))
        #expect(status == .active(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("An open-limit rule blocks once opens are exhausted")
    func exhaustedOpensBlock() {
        let rule = openLimitRule(maxOpens: 5)
        let status = rule.dto.status(at: mondayMorning, calendar: utc, usage: RuleUsageDTO(opensUsed: 5))
        #expect(status == .active(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("A spent budget on a disabled day does not block")
    func disabledDayDoesNotBlock() {
        let rule = timeLimitRule()
        rule.days = Weekday.weekends
        let status = rule.dto.status(at: mondayMorning, calendar: utc, usage: RuleUsageDTO(minutesUsed: 99))
        #expect(!status.isActive)
    }

    @Test("Unblocking a limit-blocked rule pauses it until midnight")
    func unblockPausesUntilMidnight() {
        let rule = timeLimitRule(limit: 45)
        let usage = RuleUsageDTO(minutesUsed: 45)
        #expect(RulePolicy.canUnblock(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
        #expect(RulePolicy.unblock(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(rule.pausedUntil == date(2025, 1, 7, 0, 0))
        #expect(
            rule.dto.status(at: mondayMorning, calendar: utc, usage: usage)
                == .paused(until: date(2025, 1, 7, 0, 0)))
    }

    @Test("Hard Mode locks a limit-blocked rule and its app lists")
    func hardModeLocksLimitBlock() {
        let rule = timeLimitRule(limit: 45)
        rule.hardMode = true
        let usage = RuleUsageDTO(minutesUsed: 45)
        #expect(RulePolicy.isHardLocked(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
        #expect(!RulePolicy.canUnblock(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
        #expect(
            !RulePolicy.canEditAppLists(
                snapshots: [rule].map(\.dto), usageFor: { _ in usage }, at: mondayMorning, calendar: utc))
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
        ledger.usageByRule[rule.id] = RuleUsageDTO(minutesUsed: 45)

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
        ledger.usageByRule[rule.id] = RuleUsageDTO(minutesUsed: 20)

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
        ledger.usageByRule[rule.id] = RuleUsageDTO(opensUsed: 2)

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

    let now = date(2025, 1, 6, 10, 0) // a Monday, so the every-day rules fire

    @Test("Limit rows show the daily budget, never a live count")
    func limitContextShowsBudget() {
        let idle = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(timeRule.dto.rowContext(for: idle, usage: RuleUsageDTO(), relativeTo: now) == "45m / day")

        let used = RuleUsageDTO(minutesUsed: 18) // under budget → upcoming → budget
        let active = timeRule.dto.status(at: now, calendar: utc, usage: used)
        #expect(timeRule.dto.rowContext(for: active, usage: used, relativeTo: now) == "45m / day")
    }

    @Test("A spent limit reads 'Blocked until tomorrow'; unblocking it reads Paused")
    func spentLimitContext() {
        let spent = RuleUsageDTO(minutesUsed: 45)
        let blocking = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(blocking.isActive)
        #expect(timeRule.dto.rowContext(for: blocking, usage: spent, relativeTo: now) == "Blocked until tomorrow")

        timeRule.pausedUntil = utc.date(byAdding: .hour, value: 5, to: now)
        let paused = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(timeRule.dto.rowContext(for: paused, usage: spent, relativeTo: now) == "Paused")
    }

    @Test("Home subtitles prefix the rule kind")
    func homeSubtitles() {
        let timeStatus = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(for: timeRule.dto, status: timeStatus, usage: RuleUsageDTO(), relativeTo: now)
                == "Time Limit · 45m / day")

        let openStatus = openRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(for: openRule.dto, status: openStatus, usage: RuleUsageDTO(), relativeTo: now)
                == "Open Limit · 5 opens / day")
    }
}

@MainActor
@Suite("Usage report formatter")
struct UsageReportFormatterTests {
    @Test("Formats today's total; blank under a minute")
    func formatsTotal() {
        #expect(UsageReportFormatter.todayTotal(seconds: 0) == "")
        #expect(UsageReportFormatter.todayTotal(seconds: 59) == "")
        #expect(UsageReportFormatter.todayTotal(seconds: 60) == "1m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 22 * 60) == "22m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 72 * 60) == "1h 12m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 120 * 60) == "2h today")
    }
}
