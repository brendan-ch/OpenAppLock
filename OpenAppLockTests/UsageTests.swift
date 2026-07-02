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

    @Test("RuleUsageDTO round-trips minutes and opens; legacy blobs still decode")
    func usageCodable() throws {
        let usage = RuleUsageDTO(minutesUsed: 30, opensUsed: 2)
        let data = try JSONEncoder().encode(usage)
        #expect(try JSONDecoder().decode(RuleUsageDTO.self, from: data) == usage)

        // A blob written with the old authoritative keys still decodes (extra keys ignored).
        let legacy = Data(#"{"minutesUsed":7,"opensUsed":1,"authoritativeMinutesUsed":9}"#.utf8)
        let decoded = try JSONDecoder().decode(RuleUsageDTO.self, from: legacy)
        #expect(decoded == RuleUsageDTO(minutesUsed: 7, opensUsed: 1))
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

    @Test("Pausing a limit-blocked rule sets a 15-minute pause")
    func pausePausesLimitRule() {
        let rule = timeLimitRule(limit: 45)
        let usage = RuleUsageDTO(minutesUsed: 45)
        #expect(RulePolicy.canPause(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
        #expect(RulePolicy.pause(rule, usage: usage, at: mondayMorning, calendar: utc))
        #expect(rule.pausedUntil == date(2025, 1, 6, 10, 15))
        #expect(
            rule.dto.status(at: mondayMorning, calendar: utc, usage: usage)
                == .paused(until: date(2025, 1, 6, 10, 15)))
    }

    @Test("Hard Mode locks a limit-blocked rule and its app lists")
    func hardModeLocksLimitBlock() {
        let rule = timeLimitRule(limit: 45)
        rule.hardMode = true
        let usage = RuleUsageDTO(minutesUsed: 45)
        #expect(RulePolicy.isHardLocked(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
        #expect(!RulePolicy.canPause(rule.dto, usage: usage, at: mondayMorning, calendar: utc))
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

    @Test("Scheduled-today limit rows show the reset countdown, spent or not")
    func limitContextShowsResetCountdown() {
        let idle = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            timeRule.dto.rowContext(for: idle, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Resets in 14h")

        let used = RuleUsageDTO(minutesUsed: 18) // under budget → still resets tonight
        let active = timeRule.dto.status(at: now, calendar: utc, usage: used)
        #expect(
            timeRule.dto.rowContext(for: active, usage: used, relativeTo: now, calendar: utc)
                == "Resets in 14h")
    }

    @Test("A spent limit reads 'Resets in {countdown}'; pausing it reads a resume countdown")
    func spentLimitContext() {
        let spent = RuleUsageDTO(minutesUsed: 45)
        let blocking = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(blocking.isActive)
        #expect(
            timeRule.dto.rowContext(for: blocking, usage: spent, relativeTo: now, calendar: utc)
                == "Resets in 14h")

        timeRule.pausedUntil = utc.date(byAdding: .hour, value: 5, to: now)
        let paused = timeRule.dto.status(at: now, calendar: utc, usage: spent)
        #expect(
            timeRule.dto.rowContext(for: paused, usage: spent, relativeTo: now, calendar: utc)
                == "Resumes in 5h")
    }

    @Test("Home subtitles prefix the rule kind")
    func homeSubtitles() {
        let timeStatus = timeRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(
                for: timeRule.dto, status: timeStatus, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Time Limit · Resets in 14h")

        let openStatus = openRule.dto.status(at: now, calendar: utc, usage: RuleUsageDTO())
        #expect(
            UsageDisplay.homeSubtitle(
                for: openRule.dto, status: openStatus, usage: RuleUsageDTO(), relativeTo: now, calendar: utc)
                == "Open Limit · Resets in 14h")
    }
}

@MainActor
@Suite("Usage report formatter")
struct UsageReportFormatterTests {
    @Test("Today's total: '<1m today' under a minute, 'No usage today' only at zero")
    func formatsTotal() {
        #expect(UsageReportFormatter.todayTotal(seconds: 0) == "No usage today")
        #expect(UsageReportFormatter.todayTotal(seconds: 59) == "<1m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 60) == "1m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 22 * 60) == "22m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 72 * 60) == "1h 12m today")
        #expect(UsageReportFormatter.todayTotal(seconds: 120 * 60) == "2h today")
    }

    @Test("duration renders whole hours and minutes, '0m' for zero")
    func durationStyle() {
        #expect(UsageReportFormatter.duration(minutes: 0) == "0m")
        #expect(UsageReportFormatter.duration(minutes: 45) == "45m")
        #expect(UsageReportFormatter.duration(minutes: 60) == "1h")
        #expect(UsageReportFormatter.duration(minutes: 72) == "1h 12m")
        #expect(UsageReportFormatter.duration(minutes: 125) == "2h 5m")
    }

    @Test("durationLabel reads '<1m' for non-zero sub-minute usage")
    func durationLabelStyle() {
        #expect(UsageReportFormatter.durationLabel(seconds: 0) == "0m")
        #expect(UsageReportFormatter.durationLabel(seconds: 1) == "<1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 59) == "<1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 60) == "1m")
        #expect(UsageReportFormatter.durationLabel(seconds: 72 * 60) == "1h 12m")
    }

    @Test("report sums the total and lists apps heaviest-first")
    func reportSortsApps() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Mail", seconds: 5 * 60),
            (name: "Instagram", seconds: 72 * 60),
            (name: "Safari", seconds: 18 * 60),
        ])
        #expect(data.total == "1h 35m today")            // (5 + 72 + 18) = 95 min
        #expect(data.apps.map(\.name) == ["Instagram", "Safari", "Mail"])
        #expect(data.apps.map(\.durationLabel) == ["1h 12m", "18m", "5m"])
    }

    @Test("equal-usage apps are ordered by name")
    func reportTiebreak() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Reddit", seconds: 20 * 60),
            (name: "Mastodon", seconds: 20 * 60),
        ])
        #expect(data.apps.map(\.name) == ["Mastodon", "Reddit"])
    }

    @Test("a sub-minute app is kept as a '<1m' row; a zero-second app is dropped")
    func reportKeepsSubMinuteDropsZero() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Instagram", seconds: 90 * 60),
            (name: "Blip", seconds: 30),
            (name: "Ghost", seconds: 0),
        ])
        #expect(data.apps.map(\.name) == ["Instagram", "Blip"])
        #expect(data.apps.map(\.durationLabel) == ["1h 30m", "<1m"])
    }

    @Test("sub-minute apps still sum into the total")
    func reportSubMinuteAppsSumIntoTotal() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Apollo", seconds: 40),
            (name: "Bree", seconds: 40),
        ])
        #expect(data.total == "1m today")                // 80s rounds to 1 min
        #expect(data.apps.map(\.name) == ["Apollo", "Bree"])
        #expect(data.apps.map(\.durationLabel) == ["<1m", "<1m"])
    }

    @Test("entries sharing a display name merge into one row (unique row identity)")
    func reportMergesSameNameApps() {
        let data = UsageReportFormatter.report(apps: [
            (name: "Chat", seconds: 10 * 60),
            (name: "Chat", seconds: 5 * 60),
        ])
        #expect(data.apps.map(\.name) == ["Chat"])
        #expect(data.apps.map(\.durationLabel) == ["15m"])
        #expect(data.total == "15m today")
    }

    @Test("report with no usage has no rows and reads 'No usage today'")
    func reportEmpty() {
        let data = UsageReportFormatter.report(apps: [])
        #expect(data.total == "No usage today")
        #expect(data.apps.isEmpty)
    }
}
