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
        #expect(rule.status(at: date(2025, 1, 6, 10, 0), calendar: utc) == .disabled)
    }

    @Test("Enabled rule inside its window is active until the window ends")
    func active() {
        let status = workTime().status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .active(until: date(2025, 1, 6, 17, 0)))
        #expect(status.isActive)
    }

    @Test("Enabled rule outside its window is upcoming")
    func upcoming() {
        let status = workTime().status(at: date(2025, 1, 6, 18, 0), calendar: utc)
        #expect(status == .upcoming(startsAt: date(2025, 1, 7, 9, 0)))
        #expect(!status.isActive)
    }

    @Test("A rule with no days is dormant")
    func dormant() {
        let rule = workTime()
        rule.days = []
        #expect(rule.status(at: date(2025, 1, 6, 10, 0), calendar: utc) == .dormant)
    }

    @Test("A paused rule reports paused until the window ends")
    func paused() {
        let rule = workTime()
        rule.pausedUntil = date(2025, 1, 6, 17, 0)
        let status = rule.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .paused(until: date(2025, 1, 6, 17, 0)))
        #expect(!status.isActive)
    }

    @Test("An expired pause no longer affects status")
    func expiredPause() {
        let rule = workTime()
        rule.pausedUntil = date(2025, 1, 6, 9, 30)
        let status = rule.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(status == .active(until: date(2025, 1, 6, 17, 0)))
    }

    @Test("Time-limit rules are never schedule-active")
    func timeLimitNeverActive() {
        let rule = BlockingRule(name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig()))
        let status = rule.status(at: date(2025, 1, 6, 10, 0), calendar: utc)
        #expect(!status.isActive)
        if case .upcoming = status {} else {
            Issue.record("Expected upcoming, got \(status)")
        }
    }

    @Test("Active label rounds hours up")
    func activeLabel() {
        // 11:28 → 17:00 is 5h32m; rounds up to "6h left".
        let status = workTime().status(at: date(2025, 1, 6, 11, 28), calendar: utc)
        #expect(status.label(relativeTo: date(2025, 1, 6, 11, 28)) == "6h left")
    }

    @Test("Upcoming label formats hours until start")
    func upcomingLabel() {
        // Friday 11:28 → Saturday 09:00 is 21h32m; rounds up to "Starts in 22h".
        let weekend = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)
        let friday = date(2025, 1, 10, 11, 28)
        #expect(weekend.status(at: friday, calendar: utc).label(relativeTo: friday) == "Starts in 22h")
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
        #expect(RuleStatus.paused(until: now).label(relativeTo: now) == "Paused")
    }

    // MARK: - Kind-aware row context

    /// An untouched time-limit rule has no clock window, so it shows its daily
    /// budget — never the vestigial 09:00 start as "Starts in 22h".
    @Test("Untouched time-limit rule shows its daily budget, not a clock countdown")
    func timeLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38) // past the vestigial 09:00 window start
        let status = rule.status(at: now, calendar: utc)
        #expect(rule.rowContext(for: status, usage: RuleUsage(), relativeTo: now) == "15m / day")
    }

    @Test("Untouched open-limit rule shows its daily opens budget")
    func openLimitDisplayLabel() {
        let rule = BlockingRule(
            name: "Gate Keeper", configuration: .openLimit(OpenLimitConfig(maxOpens: 5)))
        let now = date(2025, 1, 6, 11, 38)
        let status = rule.status(at: now, calendar: utc)
        #expect(rule.rowContext(for: status, usage: RuleUsage(), relativeTo: now) == "5 opens / day")
    }

    @Test("Schedule rule still shows the clock countdown")
    func scheduleDisplayLabelUnchanged() {
        let weekend = BlockingRule(name: "Weekend Zen", days: Weekday.weekends)
        let friday = date(2025, 1, 10, 11, 28)
        let status = weekend.status(at: friday, calendar: utc)
        #expect(weekend.rowContext(for: status, usage: RuleUsage(), relativeTo: friday) == "Starts in 22h")
    }

    /// Limit rules block by budget, not by the clock, so a spent one reads its
    /// usage ("15m of 15m used today"), never a countdown (that is schedule-only).
    @Test("A spent time-limit budget shows its usage, not a countdown")
    func timeLimitBlockingDisplayLabel() {
        let rule = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 15)))
        let now = date(2025, 1, 6, 11, 38)
        let usage = RuleUsage(minutesUsed: 15)
        let status = rule.status(at: now, calendar: utc, usage: usage)
        #expect(status.isActive)
        #expect(rule.rowContext(for: status, usage: usage, relativeTo: now) == "15m of 15m used today")
    }
}
