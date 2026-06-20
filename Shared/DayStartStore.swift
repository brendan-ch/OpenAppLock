//
//  DayStartStore.swift
//  OpenAppLock
//

import Foundation

/// Per-rule "last confirmed daily-activity start", written when the monitor's
/// `intervalDidStart` fires (and defensively by the foreground enforcer). Lets
/// limit enforcement reject usage checkpoints that arrive before today's
/// interval boundary has been observed — i.e. yesterday's batched threshold
/// events flushed late across midnight.
final class DayStartStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func confirmedStart(for ruleID: UUID) -> Date? {
        defaults.object(forKey: key(ruleID)) as? Date
    }

    func setConfirmedStart(_ dayStart: Date, for ruleID: UUID) {
        defaults.set(dayStart, forKey: key(ruleID))
    }

    /// Whether the confirmed start equals the start of the day containing `date`.
    func hasConfirmedStart(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current
    ) -> Bool {
        confirmedStart(for: ruleID) == calendar.startOfDay(for: date)
    }

    private func key(_ ruleID: UUID) -> String {
        "dayStart/\(ruleID.uuidString)"
    }
}
