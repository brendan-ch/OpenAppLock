//
//  RuleScheduler.swift
//  OpenAppLock
//

import CryptoKit
import DeviceActivity
import FamilyControls
import Foundation

/// Abstracts `DeviceActivityCenter` so scheduling can be unit-tested.
/// `nonisolated` + `Sendable` so `RuleScheduler.sync` can run off the main thread.
nonisolated protocol ActivityMonitoring: AnyObject, Sendable {
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
    /// Starts (or replaces) a one-shot activity spanning `start`…`end`
    /// wall-clock, carrying no events — used to re-engage a shield when a
    /// temporary pause ends (its `intervalDidEnd` wakes the monitor).
    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws
    /// Starts (or replaces) a one-shot day window spanning `start`…`end`
    /// wall-clock, carrying usage-threshold `eventMinutes` over the selection —
    /// used for a time-limit rule's self-dating per-day enforcement activity.
    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws
    func stopMonitoring(names: [String])
    var monitoredNames: [String] { get }
}

/// Mirrors rules into the shared snapshot store and reconciles
/// DeviceActivity monitoring with the enabled limit rules: each one gets a
/// daily activity (time limits with one usage checkpoint per budget minute).
/// Activities are only restarted when their configuration changes, which is
/// the purpose of the fingerprint given to each propagated rule.
///
/// `nonisolated` + `Sendable` (no mutable stored state — fingerprints live in
/// `UserDefaults`) so its `sync` can run off the main thread from
/// `RuleEnforcementEngine`.
nonisolated final class RuleScheduler: @unchecked Sendable {
    private static let fingerprintsKey = "monitoringFingerprints"

    /// How many upcoming scheduled days a time-limit rule arms ahead. **N = 1**:
    /// only the current-or-next scheduled day is armed in the foreground; the day
    /// after is armed solely by the monitor's midnight self-arm
    /// (`DeviceActivityMonitorExtension.reArmNextScheduledDay`). This is a
    /// deliberate device trial of that unverified self-arm — dropping the old
    /// N = 2 foreground buffer both halves the per-rule activity cost (so the
    /// 10-rule `RuleCreationPolicy` cap fits Apple's ~20 ceiling) and makes the
    /// self-arm's real-device reliability observable. See the day-keyed
    /// enforcement spec §5 and `RULE_HARD_CAP_AND_N1_ARMING.md`.
    static let dayActivityHorizon = 1

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

    /// A DeviceActivity activity that `sync` wants running, described completely
    /// so `reconcile` can (re)start it without re-deriving anything.
    struct PlannedActivity {
        enum Payload {
            case daily(selectionData: Data?, eventMinutes: [String: Int])
            case window(start: Int, end: Int)
            case day(from: Date, to: Date, selectionData: Data?, eventMinutes: [String: Int])
        }
        let name: String
        let fingerprint: String
        let payload: Payload
        /// Whether `reconcile` should log this restart's accounting risk: true
        /// only for the time-limit block activity, the one plan with a real
        /// usage-threshold event. `includesPastActivity` (set on every
        /// `DeviceActivityEvent` this app constructs) backfills same-interval
        /// accrual from before the restart, so a restart no longer discards the
        /// whole day — only up to the current hour is at risk, per its
        /// documented hour-rounding. Open limits carry no events at all, so
        /// there is nothing to lose.
        let resetsThresholdAccountingOnRestart: Bool
    }

    /// Reconciles monitoring against the given rule snapshots. Takes
    /// `RuleSnapshotDTO`s (not `@Model` `BlockingRule`s) so it can run off the
    /// main thread — the caller snapshots on the main actor and hands the
    /// Sendable values here. See `RuleEnforcementEngine`.
    func sync(snapshots: [RuleSnapshotDTO], at now: Date = .now, calendar: Calendar = .current) {
        snapshotsUserDefaultsStore.save(snapshots)
        Diag.log(.scheduler, "sync: \(snapshots.count) rules; mirrored snapshots")

        var plans: [PlannedActivity] = []
        for snapshot in snapshots {
            // A rule must be enabled, have days, and have apps to be monitored.
            guard snapshot.isEnabled, !snapshot.days.isEmpty,
                let selectionData = snapshot.selectionData
            else { continue }

            switch snapshot.kind {
            case .timeLimit:
                // Self-dating per-day activities (block + opt-in warn): a stale
                // cross-midnight flush carries a prior day key and is dropped.
                plans.append(
                    contentsOf: dayPlans(
                        for: snapshot, selectionData: selectionData, at: now, calendar: calendar))
            case .openLimit:
                // Open limits carry no usage events and have no stale-flush class;
                // they keep the single always-on repeating activity.
                plans.append(limitPlan(for: snapshot, selectionData: selectionData))
            case .schedule:
                plans.append(contentsOf: schedulePlans(for: snapshot))
            }
        }

        reconcile(plans)
        reapStalePauseActivities(snapshots: snapshots)
    }

    /// Starts the one-shot re-arm that re-engages `ruleID`'s shield when its
    /// temporary pause ends. The interval runs one minute past `pausedUntil` so
    /// it stays above DeviceActivity's 15-minute floor and `intervalDidEnd`
    /// fires after the pause has lapsed. Best-effort: the foreground
    /// reconciliation loop is the safety net.
    func scheduleResumeReArm(
        for ruleID: UUID, until pausedUntil: Date,
        now: Date = .now, calendar: Calendar = .current
    ) {
        guard let end = calendar.date(byAdding: .minute, value: 1, to: pausedUntil) else { return }
        let name = MonitoringPlan.pauseActivityName(for: ruleID)
        do {
            try monitor.startOneShotMonitoring(name: name, from: now, to: end)
            Diag.log(.scheduler, .event, "scheduled pause re-arm \(name)")
        } catch {
            Diag.error(.scheduler, "pause re-arm start failed \(name): \(error.localizedDescription)")
        }
    }

    /// Cancels a rule's pending pause re-arm (on resume, or when the pause is
    /// otherwise cleared). Safe to call when none is running.
    func cancelResumeReArm(for ruleID: UUID) {
        monitor.stopMonitoring(names: [MonitoringPlan.pauseActivityName(for: ruleID)])
    }

    /// Stops any `pause-` re-arm activity whose rule is no longer paused (or no
    /// longer exists) — the stop-only hygiene step that frees an activity slot
    /// after a disable/delete/resume/pause-clearing edit. Never starts a re-arm
    /// (that would push its interval forward every refresh and it would never
    /// fire), and keeps re-arms for not-yet-cleared (still `pausedUntil`) rules
    /// so a natural expiry's background re-shield still fires.
    private func reapStalePauseActivities(snapshots: [RuleSnapshotDTO]) {
        let pausedRuleIDs = Set(snapshots.filter { $0.pausedUntil != nil }.map(\.id))
        let stale = monitor.monitoredNames.filter { name in
            guard let id = MonitoringPlan.ruleID(fromPauseActivityName: name) else { return false }
            return !pausedRuleIDs.contains(id)
        }
        guard !stale.isEmpty else { return }
        Diag.log(.scheduler, "reap \(stale.count) stale pause activities: \(stale.joined(separator: ","))")
        monitor.stopMonitoring(names: stale)
    }

    /// The daily enforcement activity for an open-limit rule (time-limit rules
    /// are planned by `dayPlans` instead). Open limits carry no usage-threshold
    /// events, so a restart has no accrual to lose; it is still fingerprinted
    /// on kind, budget, and selection to detect the configuration changes that
    /// should restart the activity (e.g. an app-list swap).
    func limitPlan(for snapshot: RuleSnapshotDTO, selectionData: Data) -> PlannedActivity {
        let fingerprint = "\(snapshot.kindRaw)|\(snapshot.dailyLimitMinutes)|"
            + Self.selectionFingerprint(selectionData)
        return PlannedActivity(
            name: MonitoringPlan.dailyActivityName(for: snapshot.id),
            fingerprint: fingerprint,
            payload: .daily(selectionData: selectionData, eventMinutes: [:]),
            resetsThresholdAccountingOnRestart: false)
    }

    /// The per-day block (and, when opted in, warn) activities for a time-limit
    /// rule across the current-or-next scheduled day (N = 1). Each is a
    /// non-repeating `.day` window spanning that day; the day key in the activity
    /// name makes a cross-midnight stale flush self-identify so the monitor drops
    /// it. The day after is armed solely by the monitor's midnight self-arm, not
    /// here.
    func dayPlans(
        for snapshot: RuleSnapshotDTO, selectionData: Data,
        at now: Date, calendar: Calendar = .current
    ) -> [PlannedActivity] {
        let selectionFP = Self.selectionFingerprint(selectionData)
        let nudgeOn = NotificationPreferences(defaults: defaults).timeLimitEndingEnabled
        let warnEvents = MonitoringPlan.warnEvent(forLimit: snapshot.dailyLimitMinutes)
        var plans: [PlannedActivity] = []
        for dayStart in ScheduledDayPlanner.upcomingScheduledDayStarts(
            days: snapshot.days, from: now, count: Self.dayActivityHorizon, calendar: calendar)
        {
            let dayKey = UsageLedger.dayKey(for: dayStart, calendar: calendar)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            plans.append(
                PlannedActivity(
                    name: MonitoringPlan.dailyActivityName(for: snapshot.id, dayKey: dayKey),
                    fingerprint: "\(snapshot.kindRaw)|\(snapshot.dailyLimitMinutes)|\(selectionFP)",
                    payload: .day(
                        from: dayStart, to: dayEnd, selectionData: selectionData,
                        eventMinutes: MonitoringPlan.blockEvent(forLimit: snapshot.dailyLimitMinutes)),
                    resetsThresholdAccountingOnRestart: true))
            if nudgeOn, let warnEvents {
                plans.append(
                    PlannedActivity(
                        name: MonitoringPlan.warnActivityName(for: snapshot.id, dayKey: dayKey),
                        fingerprint: "tlwarn|\(snapshot.dailyLimitMinutes)|\(selectionFP)",
                        payload: .day(
                            from: dayStart, to: dayEnd, selectionData: selectionData,
                            eventMinutes: warnEvents),
                        resetsThresholdAccountingOnRestart: false))
            }
        }
        return plans
    }

    /// The window activities for a schedule rule (one, or two for a midnight
    /// crossing). A window encodes only its interval — days, mode and apps are
    /// read fresh by reconcile() at each callback — so it is fingerprinted on
    /// start/end alone.
    func schedulePlans(for snapshot: RuleSnapshotDTO) -> [PlannedActivity] {
        let fingerprint = "schedule|\(snapshot.startMinutes)|\(snapshot.endMinutes)"
        return scheduleWindows(for: snapshot).map { window in
            PlannedActivity(
                name: window.name,
                fingerprint: fingerprint,
                payload: .window(start: window.start, end: window.end),
                resetsThresholdAccountingOnRestart: false)
        }
    }

    /// Starts the activities whose configuration changed, stops any rule-owned
    /// activity no longer desired, and persists the fingerprints. The only place
    /// that touches the monitor or the stored fingerprints.
    private func reconcile(_ plans: [PlannedActivity]) {
        var fingerprints = storedFingerprints

        for plan in plans {
            // Adopt an activity that is already running but has no recorded
            // fingerprint — e.g. one the background monitor self-armed at midnight
            // (it never writes `monitoringFingerprints`). Recording its
            // fingerprint *without* a restart stops the next foreground sync from
            // tearing it down and re-zeroing Screen Time's usage count. A rule
            // can't be edited while the app is closed, so a self-armed activity's
            // config always matches the current plan.
            if monitor.monitoredNames.contains(plan.name), fingerprints[plan.name] == nil {
                fingerprints[plan.name] = plan.fingerprint
                continue
            }
            guard needsRestart(plan.name, plan.fingerprint, in: fingerprints) else { continue }
            if plan.resetsThresholdAccountingOnRestart {
                // EC7: `includesPastActivity` backfills same-interval accrual, so
                // a restart no longer discards the whole day — only up to the
                // current hour is at risk. Log the fingerprint change so a
                // mid-day accounting gap can still be correlated to its cause
                // (config change vs not-monitored). A new day legitimately
                // starts a fresh per-day activity name.
                let events: [String: Int]
                switch plan.payload {
                case let .daily(_, e): events = e
                case let .day(_, _, _, e): events = e
                case .window: events = [:]
                }
                Diag.log(
                    .scheduler, .event,
                    "dailyActivity restart \(plan.name): events=\(events) fp \(Self.shortFingerprint(fingerprints[plan.name]))->\(Self.shortFingerprint(plan.fingerprint)) (may lose up to the current hour of accrual)")
            }
            attemptWithFallback(name: plan.name) {
                try start(plan.payload, named: plan.name)
            } onSuccess: { fingerprints[plan.name] = plan.fingerprint }
        }

        let desiredActivityNames = Set(plans.map(\.name))
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

    /// Dispatches a plan's payload to the matching monitor start call.
    private func start(_ payload: PlannedActivity.Payload, named name: String) throws {
        switch payload {
        case let .daily(selectionData, eventMinutes):
            try monitor.startDailyMonitoring(
                name: name, selectionData: selectionData, eventMinutes: eventMinutes)
        case let .window(start, end):
            try monitor.startWindowMonitoring(
                name: name, intervalStartMinutes: start, intervalEndMinutes: end)
        case let .day(from, to, selectionData, eventMinutes):
            try monitor.startDayMonitoring(
                name: name, from: from, to: to,
                selectionData: selectionData, eventMinutes: eventMinutes)
        }
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
    private func scheduleWindows(for snapshot: RuleSnapshotDTO) -> [(name: String, start: Int, end: Int)] {
        let primary = MonitoringPlan.scheduleWindowName(for: snapshot.id)
        let late = MonitoringPlan.scheduleWindowLateName(for: snapshot.id)
        let endOfDay = 24 * 60 - 1
        let start = snapshot.startMinutes
        let end = snapshot.endMinutes

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
/// `@unchecked Sendable`: wraps a single `DeviceActivityCenter`; its calls are
/// serialized by the enforcement actor and are safe off the main thread.
nonisolated final class DeviceActivityCenterMonitor: ActivityMonitoring, @unchecked Sendable {
    private let center = DeviceActivityCenter()

    var monitoredNames: [String] {
        center.activities.map(\.rawValue)
    }

    func startDailyMonitoring(
        name: String, selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let events = DeviceActivityFactory.thresholdEvents(
            selectionData: selectionData, eventMinutes: eventMinutes)
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

    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws {
        let schedule = DeviceActivityFactory.nonRepeatingSchedule(from: start, to: end)
        try center.startMonitoring(DeviceActivityName(name), during: schedule)
    }

    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        let schedule = DeviceActivityFactory.nonRepeatingSchedule(from: start, to: end)
        let events = DeviceActivityFactory.thresholdEvents(
            selectionData: selectionData, eventMinutes: eventMinutes)
        try center.startMonitoring(DeviceActivityName(name), during: schedule, events: events)
    }

    func stopMonitoring(names: [String]) {
        center.stopMonitoring(names.map { DeviceActivityName($0) })
    }
}

/// Records scheduling calls for tests.
/// `@unchecked Sendable`: a test double; mutations are ordered behind the enforcer's `await`.
nonisolated final class MockActivityMonitor: ActivityMonitoring, @unchecked Sendable {
    private(set) var startedEvents: [String: [String: Int]] = [:]
    private(set) var startedWindows: [String: (start: Int, end: Int)] = [:]
    private(set) var startedOneShots: [String: (start: Date, end: Date)] = [:]
    private(set) var startedDayWindows: [String: (from: Date, to: Date)] = [:]
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

    func startOneShotMonitoring(name: String, from start: Date, to end: Date) throws {
        startCallCount += 1
        startedOneShots[name] = (start, end)
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }

    func startDayMonitoring(
        name: String, from start: Date, to end: Date,
        selectionData: Data?, eventMinutes: [String: Int]
    ) throws {
        startCallCount += 1
        startedEvents[name] = eventMinutes
        startedDayWindows[name] = (start, end)
        if !monitoredNames.contains(name) {
            monitoredNames.append(name)
        }
    }

    func stopMonitoring(names: [String]) {
        monitoredNames.removeAll(where: names.contains)
        for name in names {
            startedEvents[name] = nil
            startedWindows[name] = nil
            startedDayWindows[name] = nil
        }
    }
}
