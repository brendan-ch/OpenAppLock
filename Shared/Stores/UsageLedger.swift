//
//  UsageLedger.swift
//  OpenAppLock
//

import Foundation

/// Read access to per-rule, per-day usage. `nonisolated` + `Sendable` so the
/// off-main enforcement engine can read usage without hopping to the main actor.
nonisolated protocol UsageReading: AnyObject, Sendable {
    func usage(for ruleID: UUID, onDayContaining date: Date, calendar: Calendar) -> RuleUsageDTO
}

nonisolated extension UsageReading {
    func usage(for ruleID: UUID, onDayContaining date: Date) -> RuleUsageDTO {
        usage(for: ruleID, onDayContaining: date, calendar: .current)
    }
}

/// Usage bookkeeping in the shared app-group defaults, keyed by calendar day
/// and rule. Old days are simply ignored; midnight needs no reset step.
nonisolated final class UsageLedger: UsageReading, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    /// "2026-06-12" — calendar-date key so budgets roll over at midnight.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func usage(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current
    ) -> RuleUsageDTO {
        guard let data = defaults.data(forKey: key(ruleID, date, calendar)),
              let usage = try? JSONDecoder().decode(RuleUsageDTO.self, from: data)
        else { return RuleUsageDTO() }
        return usage
    }

    func setUsage(
        _ usage: RuleUsageDTO, for ruleID: UUID, onDayContaining date: Date,
        calendar: Calendar = .current
    ) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: key(ruleID, date, calendar))
    }

    /// Threshold events report cumulative totals, so minutes only move up.
    func recordMinutesUsed(
        _ minutes: Int, for ruleID: UUID, onDayContaining date: Date,
        calendar: Calendar = .current
    ) {
        var usage = self.usage(for: ruleID, onDayContaining: date, calendar: calendar)
        let prior = usage.minutesUsed
        usage.minutesUsed = max(usage.minutesUsed, minutes)
        setUsage(usage, for: ruleID, onDayContaining: date, calendar: calendar)
        Diag.log(
            .usage,
            "ledger.minutes rule-\(ruleID.uuidString.prefix(8)) \(prior)->\(usage.minutesUsed) (event=\(minutes))")
    }

    @discardableResult
    func recordOpen(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current
    ) -> RuleUsageDTO {
        var usage = self.usage(for: ruleID, onDayContaining: date, calendar: calendar)
        usage.opensUsed += 1
        setUsage(usage, for: ruleID, onDayContaining: date, calendar: calendar)
        Diag.log(
            .session, "ledger.open rule-\(ruleID.uuidString.prefix(8)) opens=\(usage.opensUsed)")
        return usage
    }

    private func key(_ ruleID: UUID, _ date: Date, _ calendar: Calendar) -> String {
        "usage/\(Self.dayKey(for: date, calendar: calendar))/\(ruleID.uuidString)"
    }
}

/// Seedable in-memory usage for tests and UI-test scenarios.
/// `@unchecked Sendable`: a test double; mutations are ordered behind the enforcer's `await`.
nonisolated final class MockUsageLedger: UsageReading, @unchecked Sendable {
    var usageByRule: [UUID: RuleUsageDTO] = [:]

    func usage(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar
    ) -> RuleUsageDTO {
        usageByRule[ruleID] ?? RuleUsageDTO()
    }
}
