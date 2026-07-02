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
    /// The user temporarily paused the current block; it resumes at the associated date.
    case paused(until: Date)
    case upcoming(startsAt: Date)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// Short status label shown on rule cards and detail sheets:
    /// "6h left", "Starts in 22h", "Resumes in 12m", "Disabled".
    func label(relativeTo now: Date) -> String {
        switch self {
        case .disabled: CopyKey.statusDisabled.string
        case .dormant: CopyKey.statusNoDaysSelected.string
        case .paused(let until): CopyKey.statusResumesIn.string(Self.countdown(from: now, to: until))
        case .active(let until): CopyKey.statusActiveLeft.string(Self.countdown(from: now, to: until))
        case .upcoming(let start): CopyKey.statusStartsIn.string(Self.countdown(from: now, to: start))
        }
    }

    /// Compact countdown: minutes under an hour,
    /// hours (rounded up) under two days, then days.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(1, Int(ceil(target.timeIntervalSince(now) / 60)))
        guard minutes >= 60 else { return CopyKey.statusCountdownMinutes.string(minutes) }
        let hours = (minutes + 59) / 60
        guard hours >= 48 else { return CopyKey.statusCountdownHours.string(hours) }
        return CopyKey.statusCountdownDays.string(hours / 24)
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
    /// lists, and as the rule-detail Status row. A single source of truth so every
    /// screen renders a given kind/state the same way.
    ///
    /// - Schedule rules read their clock status: "Ends in 6h", "Starts in 22h",
    ///   "Resumes in 12m", "Disabled", "No days selected".
    /// - Limit rules (time/open) share that wording while disabled / dormant /
    ///   paused. On a day they are scheduled — whether the budget is spent
    ///   (blocking) or still available — they read "Resets in {countdown}" to
    ///   tonight's midnight, when the daily budget resets. On a day they are not
    ///   scheduled they read the upcoming "Starts in {countdown}" to the next
    ///   enabled day. `isScheduledToday` (not the active/upcoming distinction)
    ///   picks between the two, because a limit rule is only ever `.active` on a
    ///   day it is already scheduled.
    func rowContext(
        for status: RuleStatus, usage: RuleUsageDTO, relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String {
        switch kind {
        case .schedule:
            return status.label(relativeTo: now)
        case .timeLimit, .openLimit:
            switch status {
            case .disabled, .dormant, .paused:
                return status.label(relativeTo: now)
            case .active, .upcoming:
                guard isScheduledToday(at: now, calendar: calendar),
                      let reset = calendar.nextMidnight(after: now)
                else {
                    return status.label(relativeTo: now)
                }
                return CopyKey.statusResetsIn.string(RuleStatus.countdown(from: now, to: reset))
            }
        }
    }

    /// Whether this rule belongs in Home's "Active Rules" section: enabled and
    /// not currently blocking, and either a limit rule scheduled today or a
    /// schedule rule whose next window starts within the next 24 hours. Rules
    /// blocking now live in "Currently Blocking" instead.
    func belongsInActiveRules(
        at now: Date, calendar: Calendar = .current, usage: RuleUsageDTO?
    ) -> Bool {
        guard isEnabled else { return false }
        let status = status(at: now, calendar: calendar, usage: usage)
        if status.isActive { return false }
        switch kind {
        case .timeLimit, .openLimit:
            return isScheduledToday(at: now, calendar: calendar)
        case .schedule:
            if case .upcoming(let startsAt) = status {
                return startsAt.timeIntervalSince(now) <= 24 * 60 * 60
            }
            return false
        }
    }
}
