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
    // MARK: Overrides
    
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
        // TODO: support open limits for web domains
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction, for categoryToken: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .secondaryButtonPressed:
            let lookupEnvironment = LookupEnvironment.construct()
            let snapshot = ShieldLookup.openLimitSnapshot(
                containingCategory: categoryToken, in: lookupEnvironment.snapshots,
                usage: lookupEnvironment.usage, hasActiveOpenSession: lookupEnvironment.hasActiveOpenSession,
                at: lookupEnvironment.now)
            
            if let snapshot = snapshot {
                completionHandler(grantOpen(ruleID: snapshot.id))
            } else {
                completionHandler(.close)
            }
        default:
            completionHandler(.close)
        }
    }
    
    // MARK: Open limit handler

    private func handleOpenPress(applicationToken: ApplicationToken) -> ShieldActionResponse {
        let lookupEnvironment = LookupEnvironment.construct()
        let snapshot = ShieldLookup.openLimitSnapshot(
                containingApplication: applicationToken, in: lookupEnvironment.snapshots,
                usage: lookupEnvironment.usage, hasActiveOpenSession: lookupEnvironment.hasActiveOpenSession,
                at: lookupEnvironment.now)
        
        if let snapshot = snapshot {
            return grantOpen(ruleID: snapshot.id)
        }
        return .close
    }

    /// Everything a `ShieldLookup` arbitration reads, captured at one instant so
    /// a press decides against a single consistent view of the stores.
    private struct LookupEnvironment {
        let snapshots: [RuleSnapshotDTO]
        let usage: (UUID) -> RuleUsageDTO
        let hasActiveOpenSession: (UUID) -> Bool
        let now: Date
        
        static func construct() -> LookupEnvironment {
            let ledger = UsageLedger()
            let sessions = OpenSessionStore()
            let now = Date.now
            let lookupEnvironment = LookupEnvironment(
                snapshots: RuleSnapshotUserDefaultsStore().load(),
                usage: { ledger.usage(for: $0, onDayContaining: now) },
                hasActiveOpenSession: { sessions.hasActiveSession(for: $0, at: now) },
                now: now
            )
            return lookupEnvironment
        }
    }
    
    private func grantOpen(ruleID: UUID) -> ShieldActionResponse {
        Diag.log(.session, .event, "shieldAction Open pressed rule-\(ruleID.logTag)")
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
        let schedule = DeviceActivityFactory.nonRepeatingSchedule(from: now, to: end, calendar: calendar)
        try? DeviceActivityCenter().startMonitoring(
            DeviceActivityName(MonitoringPlan.sessionActivityName(for: ruleID)),
            during: schedule
        )
    }
}
