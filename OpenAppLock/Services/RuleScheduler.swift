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
/// Activities are only restarted when their configuration changes, which is
/// the purpose of the fingerprint given to each propagated rule.
final class RuleScheduler {
    private static let fingerprintsKey = "monitoringFingerprints"

    private let monitor: ActivityMonitoring
    private let snapshotsUserDefaultsStore: RuleSnapshotUserDefaultsStore
    private let defaults: UserDefaults

    init(
        monitor: ActivityMonitoring,
        snapshots: RuleSnapshotUserDefaultsStore = RuleSnapshotUserDefaultsStore(),
        defaults: UserDefaults = AppGroup.defaults
    ) {
        self.monitor = monitor
        self.snapshotsUserDefaultsStore = snapshots
        self.defaults = defaults
    }

    func sync(rules: [BlockingRule], at now: Date = .now) {
        snapshotsUserDefaultsStore.save(rules.map(\.dto))
        Diag.log(.scheduler, "sync: \(rules.count) rules; mirrored snapshots")

        var fingerprints = storedFingerprints
        var desiredActivityNames: Set<String> = []

        for rule in rules {
            // A rule must be enabled, have days, and have apps to be monitored.
            guard rule.isEnabled, !rule.days.isEmpty,
                let selectionData = rule.appList?.selectionData
            else { continue }

            switch rule.kind {
            case .timeLimit, .openLimit:
                let name = MonitoringPlan.dailyActivityName(for: rule.id)
                desiredActivityNames.insert(name)
                let events =
                    rule.kind == .timeLimit
                    ? MonitoringPlan.blockEvent(forLimit: rule.dailyLimitMinutes)
                    : [:]
                let fingerprint = "\(rule.kindRaw)|\(rule.dailyLimitMinutes)|"
                    + Self.selectionFingerprint(selectionData)
                if needsRestart(name, fingerprint, in: fingerprints) {
                    // EC7: a restart resets threshold accounting to "from now".
                    // Log the fingerprint change so a mid-day count reset can be
                    // correlated to its cause (config change vs not-monitored).
                    Diag.log(
                        .scheduler, .event,
                        "dailyActivity restart \(name): events=\(events) fp \(Self.shortFingerprint(fingerprints[name]))->\(Self.shortFingerprint(fingerprint)) (resets threshold accounting)")
                    attemptWithFallback(name: name) {
                        try monitor.startDailyMonitoring(
                            name: name, selectionData: selectionData, eventMinutes: events)
                    } onSuccess: { fingerprints[name] = fingerprint }
                }

                // Opt-in "time limit almost up" warn activity, registered in its
                // OWN activity.
                if rule.kind == .timeLimit,
                    NotificationPreferences(defaults: defaults).timeLimitEndingEnabled,
                    let warnEvents = MonitoringPlan.warnEvent(forLimit: rule.dailyLimitMinutes)
                {
                    let warnName = MonitoringPlan.warnActivityName(for: rule.id)
                    desiredActivityNames.insert(warnName)
                    let warnFingerprint = "tlwarn|\(rule.dailyLimitMinutes)|"
                        + Self.selectionFingerprint(selectionData)
                    if needsRestart(warnName, warnFingerprint, in: fingerprints) {
                        attemptWithFallback(name: warnName) {
                            try monitor.startDailyMonitoring(
                                name: warnName, selectionData: selectionData,
                                eventMinutes: warnEvents)
                        } onSuccess: { fingerprints[warnName] = warnFingerprint }
                    }
                }

            case .schedule:
                // A window activity encodes only its interval (no events, no
                // selection); days, mode and apps are read fresh by reconcile()
                // at each callback, so only a start/end change needs a restart.
                let fingerprint = "schedule|\(rule.startMinutes)|\(rule.endMinutes)"
                for window in scheduleWindows(for: rule) {
                    desiredActivityNames.insert(window.name)
                    guard needsRestart(window.name, fingerprint, in: fingerprints) else { continue }
                    attemptWithFallback(name: window.name) {
                        try monitor.startWindowMonitoring(
                            name: window.name,
                            intervalStartMinutes: window.start,
                            intervalEndMinutes: window.end)
                    } onSuccess: { fingerprints[window.name] = fingerprint }
                }
            }
        }

        let staleActivityNames = monitor.monitoredNames.filter {
            (MonitoringPlan.ruleID(fromDailyActivityName: $0) != nil
                || MonitoringPlan.ruleID(fromScheduleWindowName: $0) != nil
                || MonitoringPlan.ruleID(fromWarnActivityName: $0) != nil)
                && !desiredActivityNames.contains($0)
        }
        if !staleActivityNames.isEmpty {
            Diag.log(.scheduler, "stop \(staleActivityNames.count) stale activities: \(staleActivityNames.joined(separator: ","))")
            monitor.stopMonitoring(names: staleActivityNames)
            for name in staleActivityNames {
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

    /// Process-stable fingerprint of an app selection.
    static func selectionFingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Compact, log-only form of a fingerprint (its trailing 12 chars), or
    /// "none" when there was no prior fingerprint. Used to make a monitoring
    /// restart's cause visible without dumping the full SHA-256.
    static func shortFingerprint(_ fingerprint: String?) -> String {
        guard let fingerprint else { return "none" }
        return String(fingerprint.suffix(12))
    }

    /// Run a best-effort callback, failing via a log, and notifying
    /// if the method ran without throwing.
    private func attemptWithFallback(name: String, _ body: () throws -> Void, onSuccess: () -> Void) {
        do {
            try body()
            onSuccess()
            Diag.log(.scheduler, .event, "started monitoring \(name)")
        } catch {
            // Best-effort; the foreground reconciliation loop is the safety net.
            // On device a failure here means background enforcement did not engage
            // (the simulator always throws — DeviceActivity is unavailable there).
            Diag.error(.scheduler, "start failed \(name): \(error.localizedDescription)")
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
