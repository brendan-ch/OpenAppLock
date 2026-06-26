//
//  UninstallProtectionEnforcer.swift
//  OpenAppLock
//

import Foundation

/// Background half of Uninstall Protection: recomputes device app-removal
/// denial from the shared rule snapshots and the persisted opt-in, then applies
/// it through the shield layer. The DeviceActivity monitor and ShieldAction
/// extensions call `reconcile()` after handling an event so protection stays in
/// step with hard-mode blocks even while the app is closed — mirroring what
/// `RuleEnforcer.refresh` does in the foreground.
struct UninstallProtectionEnforcer {
    let snapshots: RuleSnapshotUserDefaultsStore
    let shields: ShieldApplying
    /// Day-usage source for limit rules; reads the shared ledger by default.
    var ledger = UsageLedger()
    /// Where the opt-in flag is read from; the shared app-group suite by default.
    var defaults: UserDefaults = AppGroup.defaults

    func reconcile(at now: Date = .now, calendar: Calendar = .current) {
        let enabled = defaults.bool(forKey: AppGroup.uninstallProtectionKey)
        let deny = UninstallProtectionPolicy.shouldDenyAppRemoval(
            snapshots: snapshots.load(),
            enabled: enabled,
            usageFor: { ledger.usage(for: $0.id, onDayContaining: now, calendar: calendar) },
            at: now, calendar: calendar)
        shields.setAppRemovalDenied(deny)
    }
}
