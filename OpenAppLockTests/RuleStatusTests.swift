//
//  RuleStatusTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
@Suite("Rule status derivation and labels")
struct RuleStatusTests {
    /// 09:00–17:00 weekdays schedule rule (the "Work Time" preset).
    func workTime(hardMode: Bool = false) -> BlockingRule {
        BlockingRule(name: "Work Time", hardMode: hardMode)
    }

    @Test("Disabled rules report disabled regardless of the clock")
    func disabled() {
        let rule = workTime()
        rule.isEnabled = false
        #expect(rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc) == .disabled)
    }

    @Test("Enabled rule inside its window is active until the window ends")
    func active() {
        let status = workTime().dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .active(until: date(2025, 1, 6, 17, 0)))
        #expect(status.isActive)
    }

    @Test("Enabled rule outside its window is upcoming")
    func upcoming() {
        let status = workTime().dto.status(at: date(2025, 1, 6, 18, 0), calendar: utc)
        #expect(status == .upcoming(startsAt: date(2025, 1, 7, 9, 0)))
        #expect(!status.isActive)
    }

    @Test("A rule with no days is dormant")
    func dormant() {
        let rule = workTime()
        rule.days = []
        #expect(rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc) == .dormant)
    }

    @Test("A paused rule reports paused with a resume countdown")
    func paused() {
        let rule = workTime()
        rule.pausedUntil = date(2025, 1, 6, 10, 15)
        let status = rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .paused(until: date(2025, 1, 6, 10, 15)))
        #expect(!status.isActive)
        #expect(status.label(relativeTo: date(2025, 1, 6, 10, 0)) == "Resumes in 15m")
    }

    @Test("An expired pause no longer affects status")
    func expiredPause() {
        let rule = workTime()
        rule.pausedUntil = date(2025, 1, 6, 9, 30)
        let status = rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .active(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Time-limit rules are never schedule-active")
    func timeLimitNeverActive() {
        let rule = BlockingRule(name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig()))
        let status = rule.dto.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(!status.isActive)
        if case .upcoming = status {} else {
            Issue.record("Expected upcoming, got \(status)")
        }
    }

    @Test("Active label rounds hours up")
    func activeLabel() {
        // 11:28 → 17:00 is 5h32m; rounds up to "6h left".
        let status = workTime().dto.status(at: date(2025, 1, 6, 11, 28), calendar: utc)
        #expect(status.label(relativeTo: date(2025, 1, 6, 11, 28)) == "6h left")
    }

    @Test("Upcoming label formats hours until start")
    func upcomingLabel() {
        // Friday 11:28 → Saturday 09:00 is 21h32m; rounds up to "Starts in 22h".
        let weekend = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)
        let friday = date(2025, 1, 10, 11, 28)
        #expect(weekend.dto.status(at: friday, calendar: utc).label(relativeTo: friday) == "Starts in 22h")
    }

    @Test("Countdown formatting tiers", arguments: [
        (30, "30m"), (59, "59m"), (60, "1h"), (90, "2h"),
        (6 * 60, "6h"), (47 * 60, "47h"), (49 * 60, "2d"), (75 * 60, "3d"),
    ])
    func countdownTiers(minutes: Int, expected: String) {
        let now = date(2025, 1, 6, 0, 0)
        let target = utc.date(byAdding: .minute, value: minutes, to: now)!
        #expect(RuleStatus.countdown(from: now, to: target) == expected)
    }

    @Test("Countdown never reads below one minute")
    func countdownFloor() {
        let now = date(2025, 1, 6, 0, 0)
        #expect(RuleStatus.countdown(from: now, to: now.addingTimeInterval(5)) == "1m")
    }

    @Test("Static labels")
    func staticLabels() {
        let now = date(2025, 1, 6, 0, 0)
        #expect(RuleStatus.disabled.label(relativeTo: now) == "Disabled")
        #expect(RuleStatus.dormant.label(relativeTo: now) == "No days selected")
        #expect(RuleStatus.paused(until: now.addingTimeInterval(15 * 60)).label(relativeTo: now) == "Resumes in 15m")
    }

    // MARK: - Kind-aware row context

    /// An untouched time-limit rule has no clock window, so it shows its daily
    /// budget — never the vestigial 09:00 start as "Starts in 22h".
    @Test("Untouched time-limit rule shows its daily budget, not a clock countdown")
    func timeLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38) // past the vestigial 09:00 window start
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(rule.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: now) == "15m / day")
    }

    @Test("Untouched open-limit rule shows its daily opens budget")
    func openLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Gate Keeper", configuration: .openLimit(OpenLimitConfig(maxOpens: 5)))
        let now = date(2025, 1, 6, 11, 38)
        let status = rule.dto.status(at: now, calendar: utc)
        #expect(rule.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: now) == "5 opens / day")
    }

    @Test("Schedule rule still shows the clock countdown")
    func scheduleDisplayLabelUnchanged() {
        let weekend = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)
        let friday = date(2025, 1, 10, 11, 28)
        let status = weekend.dto.status(at: friday, calendar: utc)
        #expect(weekend.dto.rowContext(for: status, usage: RuleUsageDTO(), relativeTo: friday) == "Starts in 22h")
    }

    /// Limit rules block by budget, not by the clock, so a spent one reads
    /// "Blocked until tomorrow", never a countdown (that is schedule-only).
    @Test("A spent time-limit budget reads 'Blocked until tomorrow'")
    func timeLimitBlockingDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38)
        let usage = RuleUsageDTO(minutesUsed: 15)
        let status = rule.dto.status(at: now, calendar: utc, usage: usage)
        #expect(status.isActive)
        #expect(rule.dto.rowContext(for: status, usage: usage, relativeTo: now) == "Blocked until tomorrow")
    }
}

@MainActor
@Suite("Active Rules membership")
struct ActiveRulesMembershipTests {
    // Monday 08:00 — before the default 09:00–17:00 window, so a weekday
    // schedule is upcoming-today (starts in 1h).
    let now = date(2025, 1, 6, 8, 0)

    @Test("A limit scheduled today and under budget belongs in Active Rules")
    func underBudgetLimitIncluded() {
        let rule = BlockingRule(
            name: "Time Keeper",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            days: Weekday.everyDay)
        #expect(rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO(minutesUsed: 10)))
    }

    @Test("A spent (blocking) limit is excluded — it belongs in Currently Blocking")
    func spentLimitExcluded() {
        let rule = BlockingRule(
            name: "Doom Scroll",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30)),
            days: Weekday.everyDay)
        #expect(!rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO(minutesUsed: 30)))
    }

    @Test("A schedule starting within 24h is included; beyond 24h is excluded")
    func scheduleWithin24h() {
        // Default 09:00 window, weekdays → from Monday 08:00, starts in 1h.
        let soon = BlockingRule(name: "Sleep", days: Weekday.weekdays)
        #expect(soon.dto.belongsInActiveRules(at: now, calendar: utc, usage: nil))

        // Weekend-only → from Monday the next start is Saturday → beyond 24h.
        let later = BlockingRule(name: "Weekend Off", days: Weekday.weekends)
        #expect(!later.dto.belongsInActiveRules(at: now, calendar: utc, usage: nil))
    }

    @Test("A disabled rule is excluded")
    func disabledExcluded() {
        let rule = BlockingRule(
            name: "Off",
            configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
            isEnabled: false,
            days: Weekday.everyDay)
        #expect(!rule.dto.belongsInActiveRules(at: now, calendar: utc, usage: RuleUsageDTO()))
    }
}
