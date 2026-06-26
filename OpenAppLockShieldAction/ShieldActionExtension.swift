//
//  ShieldActionExtension.swift
//  OpenAppLockShieldAction
//

import DeviceActivity
import Foundation
import ManagedSettings

/// Handles shield button presses. The secondary "Open" button on an
/// open-limit shield spends one open, lifts the rule's shield, and starts a
/// one-shot DeviceActivity session after which the monitor extension
/// re-shields.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction, for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            completionHandler(handleOpenPress(applicationToken: application))
        case .firstSecondarySubmenuItemPressed, .secondSecondarySubmenuItemPressed,
            .thirdSecondarySubmenuItemPressed:
            // Our shields define no submenu items.
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction, for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction, for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .secondaryButtonPressed:
            if let snapshot = ShieldLookup.openLimitSnapshot(
                containingCategory: category, in: RuleSnapshotUserDefaultsStore().load()) {
                completionHandler(grantOpen(ruleID: snapshot.id))
            } else {
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }

    private func handleOpenPress(applicationToken: ApplicationToken) -> ShieldActionResponse {
        guard
            let snapshot = ShieldLookup.openLimitSnapshot(
                containingApplication: applicationToken, in: RuleSnapshotUserDefaultsStore().load())
        else { return .close }
        return grantOpen(ruleID: snapshot.id)
    }

    private func grantOpen(ruleID: UUID) -> ShieldActionResponse {
        Diag.log(.session, .event, "shieldAction Open pressed rule-\(ruleID.uuidString.prefix(8))")
        let enforcement = LimitEnforcement(
            snapshots: RuleSnapshotUserDefaultsStore(),
            ledger: UsageLedger(),
            shields: ManagedSettingsShieldController()
        )
        guard enforcement.handleOpenRequest(ruleID: ruleID) else {
            // Out of opens; keep the shield up (it re-renders with the
            // exhausted message on next presentation).
            return .defer
        }
        startOpenSession(ruleID: ruleID)
        // Keep Uninstall Protection in step with the (possibly changed) blocking
        // state now that an open was spent.
        UninstallProtectionEnforcer(
            snapshots: RuleSnapshotUserDefaultsStore(),
            shields: ManagedSettingsShieldController()
        ).reconcile()
        return .none
    }

    /// Times the granted open with a one-shot activity. One extra minute over
    /// the advertised session keeps the interval above DeviceActivity's
    /// 15-minute minimum.
    private func startOpenSession(ruleID: UUID) {
        let calendar = Calendar.current
        let now = Date.now
        guard
            let end = calendar.date(
                byAdding: .minute, value: MonitoringPlan.openSessionMinutes + 1, to: now)
        else { return }
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: now),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(
            DeviceActivityName(MonitoringPlan.sessionActivityName(for: ruleID)),
            during: schedule
        )
    }
}
