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

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue) {
            enforcement.handleDayStart(ruleID: ruleID)
        } else if let ruleID = MonitoringPlan.ruleID(fromScheduleWindowName: activity.rawValue) {
            // A schedule window opened: shield it (the recompute honours days,
            // pause and the midnight-crossing rule).
            scheduleEnforcement.reconcile(ruleID: ruleID)
        }
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
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name, activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let ruleID = MonitoringPlan.ruleID(fromDailyActivityName: activity.rawValue),
              let minutes = MonitoringPlan.minutes(fromEventName: event.rawValue)
        else { return }
        enforcement.handleUsageMinutes(minutes, ruleID: ruleID)
    }
}
