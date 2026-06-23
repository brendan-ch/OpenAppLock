//
//  UsageLedger.swift
//  OpenAppLock
//

import Foundation

/// What a limit rule has consumed on a given day. Written by the
/// DeviceActivity monitor (minutes) and shield-action extension (opens);
/// read by the app for display and enforcement.
struct RuleUsage: Codable, Equatable {
    var minutesUsed = 0
    var opensUsed = 0
    /// The true daily total written by the DeviceActivityReport extension while
    /// the app is foreground; preferred over `minutesUsed` when fresh.
    var authoritativeMinutesUsed: Int?
    /// When the authoritative total was computed.
    var authoritativeAsOf: Date?

    /// How long an authoritative reading is trusted before falling back to the
    /// threshold count. Tunable on device.
    static let authoritativeFreshness: TimeInterval = 120

    /// The daily minutes to use for display and the block decision: the report's
    /// authoritative total when fresh, else the threshold count.
    func effectiveMinutesUsed(
        asOf now: Date, freshness: TimeInterval = RuleUsage.authoritativeFreshness
    ) -> Int {
        if let authoritative = authoritativeMinutesUsed, let asOf = authoritativeAsOf,
           abs(now.timeIntervalSince(asOf)) <= freshness {
            return authoritative
        }
        return minutesUsed
    }
}

/// Read access to per-rule, per-day usage.
protocol UsageReading: AnyObject {
    func usage(for ruleID: UUID, onDayContaining date: Date, calendar: Calendar) -> RuleUsage
}

extension UsageReading {
    func usage(for ruleID: UUID, onDayContaining date: Date) -> RuleUsage {
        usage(for: ruleID, onDayContaining: date, calendar: .current)
    }
}

/// Usage bookkeeping in the shared app-group defaults, keyed by calendar day
/// and rule. Old days are simply ignored; midnight needs no reset step.
final class UsageLedger: UsageReading {
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
    ) -> RuleUsage {
        guard let data = defaults.data(forKey: key(ruleID, date, calendar)),
              let usage = try? JSONDecoder().decode(RuleUsage.self, from: data)
        else { return RuleUsage() }
        return usage
    }

    func setUsage(
        _ usage: RuleUsage, for ruleID: UUID, onDayContaining date: Date,
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

    /// Records the report's authoritative daily total without disturbing the
    /// monotonic threshold count.
    func recordAuthoritativeMinutes(
        _ minutes: Int, for ruleID: UUID, onDayContaining date: Date, asOf: Date,
        calendar: Calendar = .current
    ) {
        var usage = self.usage(for: ruleID, onDayContaining: date, calendar: calendar)
        usage.authoritativeMinutesUsed = minutes
        usage.authoritativeAsOf = asOf
        setUsage(usage, for: ruleID, onDayContaining: date, calendar: calendar)
    }

    @discardableResult
    func recordOpen(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current
    ) -> RuleUsage {
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
final class MockUsageLedger: UsageReading {
    var usageByRule: [UUID: RuleUsage] = [:]

    func usage(
        for ruleID: UUID, onDayContaining date: Date, calendar: Calendar
    ) -> RuleUsage {
        usageByRule[ruleID] ?? RuleUsage()
    }
}
