//
//  DeviceActivityMonitorExtension.swift
//  OpenAppLockMonitor
//

import DeviceActivity
import Foundation

/// Background half of limit-rule enforcement. Time-limit rules run a self-dating
/// per-day activity (`rule-<uuid>-<dayKey>`, plus an opt-in `tlwarn-` warn);
/// open limits keep a single repeating daily activity. This extension reacts: it
/// confirms the day-start and zeroes the ledger, records usage and blocks at the
/// budget — dropping any fire whose day key isn't today (a cross-midnight stale
/// flush) — ends granted open sessions, and self-arms the next scheduled day
/// when a per-day activity ends.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var enforcement: LimitEnforcement {
        LimitEnforcement(
            snapshots: RuleSnapshotUserDefaultsStore(),
            ledger: UsageLedger(),
            shields: ManagedSettingsShieldController()
        )
    }

    private var scheduleEnforcement: ScheduleEnforcement {
        ScheduleEnforcement(
            snapshots: RuleSnapshotUserDefaultsStore(),
            shields: ManagedSettingsShieldController()
        )
    }

    /// Re-evaluates Uninstall Protection from the snapshots + opt-in after each
    /// callback, so app-removal denial tracks hard-mode blocks even while the
    /// app is closed.
    private var uninstallProtection: UninstallProtectionEnforcer {
        UninstallProtectionEnforcer(
            snapshots: RuleSnapshotUserDefaultsStore(),
            shields: ManagedSettingsShieldController()
        )
    }

    /// A temporary pause activity reached an interval edge: recompute the rule's
    /// shield from its snapshot. At the start edge the rule is still paused, so
    /// this clears; at the end edge the pause has lapsed, so it re-shields a
    /// still-blocking rule. Open limits are never pausable.
    private func reEnforceAfterPause(ruleID: UUID) {
        guard let snapshot = RuleSnapshotUserDefaultsStore().snapshot(for: ruleID) else { return }
        switch snapshot.kind {
        case .schedule: scheduleEnforcement.reconcile(ruleID: ruleID)
        case .timeLimit: enforcement.handlePauseEnded(ruleID: ruleID)
        case .openLimit: break
        }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Diag.log(.monitor, .event, "intervalDidStart \(activity.rawValue)")
        if let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue) {
            enforcement.handleDayStart(ruleID: ruleID)
        } else if let ruleID = MonitoringPlan.ruleID(fromScheduleWindowName: activity.rawValue) {
            // A schedule window opened: shield it (the recompute honours days,
            // pause and the midnight-crossing rule).
            scheduleEnforcement.reconcile(ruleID: ruleID)
        } else if let ruleID = MonitoringPlan.ruleID(fromPauseActivityName: activity.rawValue) {
            // A temporary pause began: recompute (clears while still paused).
            reEnforceAfterPause(ruleID: ruleID)
        }
        uninstallProtection.reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Diag.log(.monitor, .event, "intervalDidEnd \(activity.rawValue)")
        if let ruleID = MonitoringPlan.ruleID(fromSessionActivityName: activity.rawValue) {
            enforcement.handleOpenSessionEnded(ruleID: ruleID)
            DeviceActivityCenter().stopMonitoring([activity])
        } else if let ruleID = MonitoringPlan.ruleID(fromScheduleWindowName: activity.rawValue) {
            // A schedule window closed (or its evening half ended at 23:59):
            // recompute so a still-active window stays shielded and a finished
            // one clears.
            scheduleEnforcement.reconcile(ruleID: ruleID)
        } else if let ruleID = MonitoringPlan.ruleID(fromPauseActivityName: activity.rawValue) {
            // A temporary pause elapsed: recompute (re-shields a still-blocking
            // rule) and stop the one-shot.
            reEnforceAfterPause(ruleID: ruleID)
            DeviceActivityCenter().stopMonitoring([activity])
        } else if MonitoringPlan.dayKey(fromActivityName: activity.rawValue) != nil,
            MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue) != nil
                || MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) != nil
        {
            // A per-day block/warn activity ended at midnight: arm the next
            // scheduled day and stop this one. The day-key guard means open
            // limit's legacy un-keyed repeating activity is left to roll over.
            reArmNextScheduledDay(endedActivity: activity.rawValue)
            DeviceActivityCenter().stopMonitoring([activity])
        }
        uninstallProtection.reconcile()
    }

    /// A per-day block or warn activity ended at midnight: register the same
    /// activity kind for the rule's next scheduled day, so background enforcement
    /// continues without a foreground sync. Best-effort — the foreground N=2
    /// arming (`RuleScheduler.dayPlans`) is the safety net. See the day-keyed
    /// enforcement spec §5. Device-only: the simulator delivers no callbacks.
    private func reArmNextScheduledDay(endedActivity name: String) {
        let isWarn = MonitoringPlan.ruleID(fromWarnActivityName: name) != nil
        guard
            let ruleID = isWarn
                ? MonitoringPlan.ruleID(fromWarnActivityName: name)
                : MonitoringPlan.ruleID(fromDailyActivityName: name),
            let endedKey = MonitoringPlan.dayKey(fromActivityName: name),
            let snapshot = RuleSnapshotUserDefaultsStore().snapshot(for: ruleID),
            snapshot.isEnabled, snapshot.kind == .timeLimit
        else { return }

        let calendar = Calendar.current
        // Anchor on the ended interval's own day (from its key) so a late
        // intervalDidEnd still advances to the correct next scheduled day.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let events: [String: Int]? =
            isWarn
            ? MonitoringPlan.warnEvent(forLimit: snapshot.dailyLimitMinutes)
            : MonitoringPlan.blockEvent(forLimit: snapshot.dailyLimitMinutes)
        guard let endedDay = formatter.date(from: endedKey),
            let nextStart = ScheduledDayPlanner.nextScheduledDayStart(
                after: endedDay, days: snapshot.days, calendar: calendar),
            let nextEnd = calendar.date(byAdding: .day, value: 1, to: nextStart),
            let events
        else {
            Diag.log(
                .scheduler,
                "self-arm rule-\(ruleID.uuidString.prefix(8)): no next scheduled day after \(endedKey)")
            return
        }

        let nextKey = UsageLedger.dayKey(for: nextStart, calendar: calendar)
        let nextName =
            isWarn
            ? MonitoringPlan.warnActivityName(for: ruleID, dayKey: nextKey)
            : MonitoringPlan.dailyActivityName(for: ruleID, dayKey: nextKey)
        let center = DeviceActivityCenter()
        // The foreground net (N=2) may already have armed the next scheduled day
        // from its own midnight; restarting it here would reset Screen Time's
        // usage count to "from now" (EC7), losing that day's morning accrual.
        // Only arm when it isn't already running.
        guard !center.activities.contains(DeviceActivityName(nextName)) else {
            Diag.log(.scheduler, "self-arm \(nextName): already armed, skipping")
            return
        }
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: nextStart),
            intervalEnd: calendar.dateComponents(components, from: nextEnd),
            repeats: false)
        let selection = AppSelectionCodec.decode(snapshot.selectionData)
        let deviceEvents = Dictionary(
            uniqueKeysWithValues: events.map { eventName, minutes in
                (
                    DeviceActivityEvent.Name(eventName),
                    DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: true
                    )
                )
            })
        do {
            try center.startMonitoring(
                DeviceActivityName(nextName), during: schedule, events: deviceEvents)
            Diag.log(.scheduler, .event, "self-arm \(nextName) (after \(endedKey))")
        } catch {
            Diag.error(.scheduler, "self-arm start failed \(nextName): \(error.localizedDescription)")
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name, activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        Diag.log(
            .monitor, .event,
            "eventDidReachThreshold event=\(event.rawValue) activity=\(activity.rawValue)")
        // The opt-in warn activity fires ~5 min before the budget on its own
        // activity, so check it first — its events don't use the `minutes-`
        // naming the block path parses, and it records no usage.
        if let ruleID = MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) {
            LimitWarningNotifier().notifyIfEligible(
                ruleID: ruleID,
                activityDayKey: MonitoringPlan.dayKey(fromActivityName: activity.rawValue))
            return
        }
        guard let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue),
              let minutes = MonitoringPlan.minutes(fromEventName: event.rawValue)
        else { return }
        enforcement.handleUsageMinutes(
            minutes, ruleID: ruleID,
            activityDayKey: MonitoringPlan.dayKey(fromActivityName: activity.rawValue))
        uninstallProtection.reconcile()
    }
}
