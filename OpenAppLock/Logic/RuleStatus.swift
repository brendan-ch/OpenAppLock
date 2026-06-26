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

extension RuleSnapshotDTO {
    /// Live status of this rule, for the UI. Derived from the shared
    /// `activation` primitive, with the disabled / dormant distinctions the UI
    /// needs layered on top: schedule rules block by the clock; limit rules
    /// block once the day's budget is spent on an enabled day; without usage
    /// data a limit rule reports upcoming.
    func status(
        at now: Date = .now, calendar: Calendar = .current, usage: RuleUsageDTO? = nil
    ) -> RuleStatus {
        guard isEnabled else { return .disabled }
        guard !days.isEmpty else { return .dormant }
        switch activation(usage: usage, at: now, calendar: calendar) {
        case .active(let until): return .active(until: until)
        case .paused(let until): return .paused(until: until)
        case .inactive(let nextStart):
            return nextStart.map(RuleStatus.upcoming(startsAt:)) ?? .dormant
        }
    }

    /// The live "context" line shown under a rule's name on the Home and Rules
    /// lists, and as the rule-detail caption. A single source of truth so every
    /// screen renders a given kind/state the same way.
    ///
    /// - Schedule rules read their clock status: "6h left", "Starts in 22h",
    ///   "Paused", "Disabled", "No days selected".
    /// - Limit rules share that wording while disabled / dormant / paused;
    ///   otherwise they read their budget — live usage once the rule has been
    ///   used today ("18m of 45m used"), and the plain daily allowance while
    ///   still untouched ("45m / day"). A spent limit therefore reads
    ///   "45m of 45m used", never a clock countdown.
    func rowContext(for status: RuleStatus, usage: RuleUsageDTO, relativeTo now: Date) -> String {
        switch kind {
        case .schedule:
            return status.label(relativeTo: now)
        case .timeLimit, .openLimit:
            switch status {
            case .disabled, .dormant, .paused:
                return status.label(relativeTo: now)
            case .active:
                // A spent budget blocks for the rest of the day; the detail row
                // ("Then block until: Tomorrow") names the same moment.
                return "Blocked until tomorrow"
            case .upcoming:
                return UsageDisplay.budgetPhrase(for: self)
            }
        }
    }
}
