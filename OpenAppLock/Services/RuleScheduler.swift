//
//  RuleScheduler.swift
//  OpenAppLock
//

import CryptoKit
import DeviceActivity
import FamilyControls
import Foundation

/// Abstracts `DeviceActivityCenter` so scheduling can be unit-tested.
protocol ActivityMonitoring: AnyObject {
    /// Starts (or replaces) an always-on, midnight-to-midnight repeating
    /// activity. `eventMinutes` maps event names to cumulative usage
    /// thresholds (in minutes) over the rule's selection.
    func startDailyMonitoring(
        name: String, selectionData: Data?, eventMinutes: [String: Int]
    ) throws
    /// Starts (or replaces) a repeating window activity spanning
    /// `intervalStartMinutes`…`intervalEndMinutes` (minutes from midnight),
    /// carrying no events — used to wake the monitor at a schedule rule's
    /// window edges so its shield engages in the background.
    func startWindowMonitoring(
        name: String, intervalStartMinutes: Int, intervalEndMinutes: Int
    ) throws
    func stopMonitoring(names: [String])
    var monitoredNames: [String] { get }
}

/// Mirrors rules into the shared snapshot store and reconciles
/// DeviceActivity monitoring with the enabled limit rules: each one gets a
/// daily activity (time limits with one usage checkpoint per budget minute).
/// Activities are only restarted when their configuration changes — a
/// restart resets checkpoint accounting to "usage from now on".
final class RuleScheduler {
    private static let fingerprintsKey = "monitoringFingerprints"

    private let monitor: ActivityMonitoring
    private let snapshots: RuleSnapshotStore
    private let defaults: UserDefaults

    init(
        monitor: ActivityMonitoring,
        snapshots: RuleSnapshotStore = RuleSnapshotStore(),
        defaults: UserDefaults = AppGroup.defaults
    ) {
        self.monitor = monitor
        self.snapshots = snapshots
        self.defaults = defaults
    }

    func sync(rules: [BlockingRule], at now: Date = .now) {
        snapshots.save(rules.map(RuleSnapshot.init))

        var fingerprints = storedFingerprints
        var desiredNames: Set<String> = []

        for rule in rules {
            // A rule must be enabled, have days, and have apps to be monitored.
            guard rule.isEnabled, !rule.days.isEmpty,
                let selectionData = rule.appList?.selectionData
            else { continue }

            switch rule.kind {
            case .timeLimit, .openLimit:
                let name = MonitoringPlan.dailyActivityName(for: rule.id)
                desiredNames.insert(name)
                let events =
                    rule.kind == .timeLimit
                    ? MonitoringPlan.minuteEvents(forLimit: rule.dailyLimitMinutes)
                    : [:]
                let fingerprint = "\(rule.kindRaw)|\(rule.dailyLimitMinutes)|"
                    + Self.selectionFingerprint(selectionData)
                guard needsRestart(name, fingerprint, in: fingerprints) else { continue }
                start(name: name) {
                    try monitor.startDailyMonitoring(
                        name: name, selectionData: selectionData, eventMinutes: events)
                } onStarted: { fingerprints[name] = fingerprint }

            case .schedule:
                // A window activity encodes only its interval (no events, no
                // selection); days, mode and apps are read fresh by reconcile()
                // at each callback, so only a start/end change needs a restart.
                let fingerprint = "schedule|\(rule.startMinutes)|\(rule.endMinutes)"
                for window in scheduleWindows(for: rule) {
                    desiredNames.insert(window.name)
                    guard needsRestart(window.name, fingerprint, in: fingerprints) else { continue }
                    start(name: window.name) {
                        try monitor.startWindowMonitoring(
                            name: window.name,
                            intervalStartMinutes: window.start,
                            intervalEndMinutes: window.end)
                    } onStarted: { fingerprints[window.name] = fingerprint }
                }
            }
        }

        let stale = monitor.monitoredNames.filter {
            (MonitoringPlan.ruleID(fromDailyActivityName: $0) != nil
                || MonitoringPlan.ruleID(fromScheduleWindowName: $0) != nil)
                && !desiredNames.contains($0)
        }
        if !stale.isEmpty {
            monitor.stopMonitoring(names: stale)
            for name in stale {
                fingerprints[name] = nil
            }
        }
        storedFingerprints = fingerprints
    }

    /// Whether `name` should be (re)started: its configuration changed, or the
    /// system isn't actually monitoring it (e.g. a prior start threw).
    private func needsRestart(
        _ name: String, _ fingerprint: String, in fingerprints: [String: String]
    ) -> Bool {
        fingerprints[name] != fingerprint || !monitor.monitoredNames.contains(name)
    }

    /// Process-stable fingerprint of an app selection. `Data.hashValue` is
    /// seeded randomly per process, so feeding it into the monitoring
    /// fingerprint changed the fingerprint on every launch — restarting each
    /// limit activity and resetting its threshold accounting. SHA-256 is
    /// deterministic across launches, so an unchanged selection keeps the same
    /// fingerprint and the activity is left running.
    static func selectionFingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs a best-effort `startMonitoring` call. Monitoring throws on the
    /// simulator, when authorization is missing, and when the activity cap or
    /// minimum interval is exceeded; the next sync retries.
    private func start(name: String, _ body: () throws -> Void, onStarted: () -> Void) {
        do {
            try body()
            onStarted()
        } catch {
            // Best-effort; the foreground reconciliation loop is the safety net.
        }
    }

    /// The DeviceActivity window activities for a schedule rule. Normal windows
    /// map to one activity; midnight-crossing windows split into an evening half
    /// (to 23:59) and a morning half (from 00:00); a `start == end` window is
    /// treated as all-day.
    private func scheduleWindows(for rule: BlockingRule) -> [(name: String, start: Int, end: Int)] {
        let primary = MonitoringPlan.scheduleWindowName(for: rule.id)
        let late = MonitoringPlan.scheduleWindowLateName(for: rule.id)
        let endOfDay = 24 * 60 - 1
        let start = rule.startMinutes
        let end = rule.endMinutes

        if start < end {
            return [(name: primary, start: start, end: end)]
        }
        if start == end {
            return [(name: primary, start: 0, end: endOfDay)]
        }
        var windows = [(name: primary, start: start, end: endOfDay)]
        if end > 0 {
            windows.append((name: late, start: 0, end: end))
        }
        return windows
    }

    private var storedFingerprints: [String: String] {
        get { defaults.dictionary(forKey: Self.fingerprintsKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Self.fingerprintsKey) }
    }
}

extension RuleSnapshot {
    init(rule: BlockingRule) {
        self.init(
            id: rule.id,
            name: rule.name,
            kindRaw: rule.kindRaw,
            isEnabled: rule.isEnabled,
            hardMode: rule.hardMode,
            blockAdultContent: rule.blockAdultContent,
            selectionModeRaw: rule.selectionModeRaw,
            selectionData: rule.appList?.selectionData,
            dayNumbers: rule.dayNumbers,
            startMinutes: rule.startMinutes,
            endMinutes: rule.endMinutes,
            dailyLimitMinutes: rule.dailyLimitMinutes,
            maxOpens: rule.maxOpens,
            pausedUntil: rule.pausedUntil
        )
    }
}

/// Real DeviceActivity scheduling. Each daily activity repeats from midnight
/// to 23:59 with usage-threshold events over the rule's selection.
final class DeviceActivityCenterMonitor: ActivityMonitoring {
    private let center = DeviceActivityCenter()

    var monitoredNames: [String] {
        center.activities.map(\.rawValue)
    }

    func startDailyMonitoring(
        name: String, selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        let selection = AppSelectionCodec.decode(selectionData)
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let events = Dictionary(
            uniqueKeysWithValues: eventMinutes.map { eventName, minutes in
                (
                    DeviceActivityEvent.Name(eventName),
                    DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes)
                    )
                )
            }
        )
        try center.startMonitoring(DeviceActivityName(name), during: schedule, events: events)
    }

    func startWindowMonitoring(
        name: String, intervalStartMinutes: Int, intervalEndMinutes: Int
    ) throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(
                hour: intervalStartMinutes / 60, minute: intervalStartMinutes % 60),
            intervalEnd: DateComponents(
                hour: intervalEndMinutes / 60, minute: intervalEndMinutes % 60),
            repeats: true
        )
        try center.startMonitoring(DeviceActivityName(name), during: schedule)
    }

    func stopMonitoring(names: [String]) {
        center.stopMonitoring(names.map { DeviceActivityName($0) })
    }
}

/// Records scheduling calls for tests.
final class MockActivityMonitor: ActivityMonitoring {
    private(set) var startedEvents: [String: [String: Int]] = [:]
    private(set) var startedWindows: [String: (start: Int, end: Int)] = [:]
    private(set) var startCallCount = 0
    private(set) var monitoredNames: [String] = []

    func startDailyMonitoring(
        name: String, selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        startCallCount += 1
        startedEvents[name] = eventMinutes
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }

    func startWindowMonitoring(
        name: String, intervalStartMinutes: Int, intervalEndMinutes: Int
    ) throws {
        startCallCount += 1
        startedWindows[name] = (intervalStartMinutes, intervalEndMinutes)
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }

    func stopMonitoring(names: [String]) {
        monitoredNames.removeAll(where: names.contains)
        for name in names {
            startedEvents[name] = nil
            startedWindows[name] = nil
        }
    }
}
