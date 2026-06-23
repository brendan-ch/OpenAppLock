//
//  DeviceActivityMonitorExtension.swift
//  OpenAppLockMonitor
//

import DeviceActivity
import Foundation

/// Background half of limit-rule enforcement. The app schedules a daily
/// activity per limit rule (with per-minute usage checkpoints for time
/// limits); this extension reacts: it resets shields at midnight, records
/// usage minutes, blocks at the budget, and ends granted open sessions.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var enforcement: LimitEnforcement {
        LimitEnforcement(
            snapshots: RuleSnapshotStore(),
            ledger: UsageLedger(),
            shields: ManagedSettingsShieldController()
        )
    }

    private var scheduleEnforcement: ScheduleEnforcement {
        ScheduleEnforcement(
            snapshots: RuleSnapshotStore(),
            shields: ManagedSettingsShieldController()
        )
    }

    /// Re-evaluates Uninstall Protection from the snapshots + opt-in after each
    /// callback, so app-removal denial tracks hard-mode blocks even while the
    /// app is closed.
    private var uninstallProtection: UninstallProtectionEnforcer {
        UninstallProtectionEnforcer(
            snapshots: RuleSnapshotStore(),
            shields: ManagedSettingsShieldController()
        )
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue) {
            enforcement.handleDayStart(ruleID: ruleID)
        } else if let ruleID = MonitoringPlan.ruleID(fromScheduleWindowName: activity.rawValue) {
            // A schedule window opened: shield it (the recompute honours days,
            // pause and the midnight-crossing rule).
            scheduleEnforcement.reconcile(ruleID: ruleID)
        }
        uninstallProtection.reconcile()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if let ruleID = MonitoringPlan.ruleID(fromSessionActivityName: activity.rawValue) {
            enforcement.handleOpenSessionEnded(ruleID: ruleID)
            DeviceActivityCenter().stopMonitoring([activity])
        } else if let ruleID = MonitoringPlan.ruleID(fromScheduleWindowName: activity.rawValue) {
            // A schedule window closed (or its evening half ended at 23:59):
            // recompute so a still-active window stays shielded and a finished
            // one clears.
            scheduleEnforcement.reconcile(ruleID: ruleID)
        }
        uninstallProtection.reconcile()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name, activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        // The opt-in warn activity fires ~5 min before the budget on its own
        // activity, so check it first — its events don't use the `minutes-`
        // naming the block path parses, and it records no usage.
        if let ruleID = MonitoringPlan.ruleID(fromWarnActivityName: activity.rawValue) {
            LimitWarningNotifier().notifyIfEligible(ruleID: ruleID)
            return
        }
        guard let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue),
              let minutes = MonitoringPlan.minutes(fromEventName: event.rawValue)
        else { return }
        enforcement.handleUsageMinutes(minutes, ruleID: ruleID)
        uninstallProtection.reconcile()
    }
}
