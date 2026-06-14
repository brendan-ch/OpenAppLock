//
//  SampleRules.swift
//  OpenAppLock
//

import Foundation
import SwiftData

/// Builds deterministic rules for UI-test scenarios, positioned relative to
/// "now" so an active window is genuinely active whenever the test runs.
enum SampleRules {
    static func seed(
        _ scenario: LaunchConfiguration.SeedScenario,
        into context: ModelContext,
        usage: MockUsageLedger? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        // Shared list so seeded rules demonstrate the app-list UI. The count
        // is display-only; UI tests never decode real tokens.
        let distractions = AppList(name: "Distractions", selectionCount: 3)
        context.insert(distractions)

        let rules: [BlockingRule]
        switch scenario {
        case .standard:
            rules = [
                activeRule(named: "Work Time", hardMode: false, now: now, calendar: calendar),
                upcomingRule(named: "Sleep", now: now, calendar: calendar),
            ]
        case .hardModeActive:
            rules = [
                activeRule(named: "Locked In", hardMode: true, now: now, calendar: calendar),
                upcomingRule(named: "Sleep", now: now, calendar: calendar),
            ]
        case .limits:
            let timeKeeper = BlockingRule(
                name: "Time Keeper",
                configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
                days: Weekday.everyDay)
            let gateKeeper = BlockingRule(
                name: "Gate Keeper",
                configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
                days: Weekday.everyDay)
            let doomScroll = BlockingRule(
                name: "Doom Scroll",
                configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30)),
                days: Weekday.everyDay)
            usage?.usageByRule[timeKeeper.id] = RuleUsage(minutesUsed: 18)
            usage?.usageByRule[gateKeeper.id] = RuleUsage(opensUsed: 2)
            usage?.usageByRule[doomScroll.id] = RuleUsage(minutesUsed: 30)
            rules = [timeKeeper, gateKeeper, doomScroll]
        }
        // Relationships are wired only after both sides are managed
        // (see BlockingRule.appList).
        for rule in rules {
            context.insert(rule)
            rule.appList = distractions
        }
    }

    /// A schedule rule whose window started up to an hour ago and runs for
    /// several hours, clamped so it never crosses midnight accidentally.
    static func activeRule(
        named name: String, hardMode: Bool, now: Date, calendar: Calendar = .current
    ) -> BlockingRule {
        let nowMinutes = minutesIntoDay(of: now, calendar: calendar)
        let start = max(0, nowMinutes - 60)
        let end = min(24 * 60 - 1, nowMinutes + 6 * 60)
        return BlockingRule(
            name: name,
            configuration: .schedule(ScheduleConfig(startMinutes: start, endMinutes: end)),
            hardMode: hardMode,
            days: Weekday.everyDay
        )
    }

    /// A schedule rule starting a couple of hours from now (possibly wrapping
    /// past midnight, which simply makes it start tomorrow).
    static func upcomingRule(
        named name: String, now: Date, calendar: Calendar = .current
    ) -> BlockingRule {
        let nowMinutes = minutesIntoDay(of: now, calendar: calendar)
        let start = (nowMinutes + 2 * 60) % (24 * 60)
        let end = (start + 8 * 60) % (24 * 60)
        return BlockingRule(
            name: name,
            configuration: .schedule(ScheduleConfig(startMinutes: start, endMinutes: end)),
            days: Weekday.everyDay
        )
    }

    private static func minutesIntoDay(of date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
