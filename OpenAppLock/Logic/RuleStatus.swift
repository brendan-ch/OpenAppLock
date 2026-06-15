//
//  RuleStatus.swift
//  OpenAppLock
//

import Foundation

/// The live state of a rule at a moment in time. Derived, never stored.
enum RuleStatus: Equatable, Sendable {
    case disabled
    /// Enabled but no days selected, so it never fires.
    case dormant
    /// Currently blocking; ends at the associated date.
    case active(until: Date)
    /// The user unblocked the current window; blocking resumes at the next window.
    case paused(until: Date)
    case upcoming(startsAt: Date)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// Short status label shown on rule cards and detail sheets:
    /// "6h left", "Starts in 22h", "Paused", "Disabled".
    func label(relativeTo now: Date) -> String {
        switch self {
        case .disabled: "Disabled"
        case .dormant: "No days selected"
        case .paused: "Paused"
        case .active(let until): "\(Self.countdown(from: now, to: until)) left"
        case .upcoming(let start): "Starts in \(Self.countdown(from: now, to: start))"
        }
    }

    /// Compact countdown: minutes under an hour,
    /// hours (rounded up) under two days, then days.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int(ceil(target.timeIntervalSince(now) / 60)))
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = (minutes + 59) / 60
        guard hours >= 48 else { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

extension BlockingRule {
    /// Live status of this rule. Schedule rules derive it from their time
    /// window. Time/open-limit rules derive it from the day's usage: once the
    /// budget is spent on an enabled day they are active (blocking) until the
    /// next midnight; without usage data they report upcoming.
    func status(
        at now: Date = .now, calendar: Calendar = .current, usage: RuleUsage? = nil
    ) -> RuleStatus {
        guard isEnabled else { return .disabled }
        guard !days.isEmpty else { return .dormant }

        guard kind == .schedule else {
            if let usage, isScheduledToday(at: now, calendar: calendar),
               limitReached(given: usage),
               let midnight = calendar.nextMidnight(after: now) {
                if let pausedUntil, pausedUntil > now {
                    return .paused(until: min(pausedUntil, midnight))
                }
                return .active(until: midnight)
            }
            guard let next = schedule.nextStart(after: now, calendar: calendar) else {
                return .dormant
            }
            return .upcoming(startsAt: next)
        }

        if let window = schedule.activeWindow(containing: now, calendar: calendar) {
            if let pausedUntil, pausedUntil > now {
                return .paused(until: min(pausedUntil, window.end))
            }
            return .active(until: window.end)
        }
        if let next = schedule.nextStart(after: now, calendar: calendar) {
            return .upcoming(startsAt: next)
        }
        return .dormant
    }

    /// The live "context" line shown under a rule's name on the Home and Rules
    /// lists, and as the rule-detail caption. A single source of truth so every
    /// screen renders a given kind/state the same way.
    ///
    /// - Schedule rules read their clock status: "6h left", "Starts in 22h",
    ///   "Paused", "Disabled", "No days selected".
    /// - Limit rules share that wording while disabled / dormant / paused;
    ///   otherwise they read their budget — live usage once the rule has been
    ///   used today ("18m of 45m used today"), and the plain daily allowance
    ///   while still untouched ("45m / day"). A spent limit therefore reads
    ///   "45m of 45m used today", never a clock countdown.
    func rowContext(for status: RuleStatus, usage: RuleUsage, relativeTo now: Date) -> String {
        switch configuration {
        case .schedule:
            return status.label(relativeTo: now)
        case .timeLimit, .openLimit:
            switch status {
            case .disabled, .dormant, .paused:
                return status.label(relativeTo: now)
            case .active, .upcoming:
                let usedToday = usage.minutesUsed > 0 || usage.opensUsed > 0
                return usedToday
                    ? UsageDisplay.usagePhrase(for: self, usage: usage)
                    : UsageDisplay.budgetPhrase(for: self)
            }
        }
    }

    /// Whether the rule's enabled days include the day containing `now`.
    func isScheduledToday(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: now)) else {
            return false
        }
        return days.contains(weekday)
    }

    /// Whether the given usage exhausts this rule's daily budget.
    /// Always false for schedule rules — they block by the clock.
    func limitReached(given usage: RuleUsage) -> Bool {
        switch configuration {
        case .schedule: false
        case .timeLimit(let config): usage.minutesUsed >= config.dailyLimitMinutes
        case .openLimit(let config): usage.opensUsed >= config.maxOpens
        }
    }
}

extension Calendar {
    /// The first instant of the day after the one containing `date` — the
    /// "Tomorrow" reset point for spent limit budgets.
    func nextMidnight(after date: Date) -> Date? {
        self.date(byAdding: .day, value: 1, to: startOfDay(for: date))
    }
}
