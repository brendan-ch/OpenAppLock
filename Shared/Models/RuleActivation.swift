//
//  RuleActivation.swift
//  OpenAppLock
//

import Foundation

/// The live blocking state of a rule at a moment in time — the single source of
/// temporal truth that both the UI status (`RuleStatus`) and the background
/// enforcement (`UninstallProtectionPolicy`) derive from, so the foreground and
/// background paths can never disagree.
///
/// The *event-driven* extension enforcers (`ScheduleEnforcement`,
/// `LimitEnforcement`) deliberately do not call `activation`: they react to
/// specific Screen Time callbacks (a window edge, a usage checkpoint, an open
/// press) rather than deriving "is it blocking now", so they compose the same
/// sub-primitives (`RuleSchedule.isActive`, `isScheduledToday`, `limitReached`,
/// `isPaused`) directly. Keep their blocking semantics in step with this type.
nonisolated enum RuleActivation: Equatable, Sendable {
    /// Not blocking now. `nextStart` is when the rule's next window begins, or
    /// nil when it never will (disabled, or no days selected).
    case inactive(nextStart: Date?)
    /// Currently blocking; ends at the associated date.
    case active(until: Date)
    /// Would be blocking, but the user temporarily paused it until the associated date.
    case paused(until: Date)

    var isBlocking: Bool {
        if case .active = self { return true }
        return false
    }
}

nonisolated extension RuleSnapshotDTO {
    /// Whether this rule is blocking right now, and until/from when. Schedule
    /// rules block by the clock; limit rules block once the day's budget is spent
    /// on an enabled day (requires usage). A pause only surfaces when the rule
    /// would otherwise be blocking.
    func activation(
        usage: RuleUsageDTO?, at now: Date = .now, calendar: Calendar = .current
    ) -> RuleActivation {
        guard isEnabled else { return .inactive(nextStart: nil) }

        let currentBlockEnd: Date?
        switch kind {
        case .schedule:
            currentBlockEnd = schedule.activeWindow(containing: now, calendar: calendar)?.end
        case .timeLimit, .openLimit:
            if let usage, isScheduledToday(at: now, calendar: calendar),
               limitReached(given: usage, at: now) {
                currentBlockEnd = calendar.nextMidnight(after: now)
            } else {
                currentBlockEnd = nil
            }
        }

        guard let end = currentBlockEnd else {
            return .inactive(nextStart: schedule.nextStart(after: now, calendar: calendar))
        }
        // A pause only surfaces when the rule would otherwise be blocking, and
        // never outlasts the block itself.
        if let pausedUntil, pausedUntil > now {
            return .paused(until: min(pausedUntil, end))
        }
        return .active(until: end)
    }
}
