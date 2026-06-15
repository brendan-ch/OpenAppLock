//
//  UninstallProtectionEnforcerTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

/// The background (extension) path that recomputes app-removal denial from the
/// shared snapshots + the persisted opt-in, mirroring `RuleEnforcer.refresh`'s
/// foreground decision.
@MainActor
@Suite("Uninstall protection background enforcer")
struct UninstallProtectionEnforcerTests {
    let mondayDuringWork = date(2025, 1, 6, 10, 0)  // inside the default 09:00–17:00
    let mondayEvening = date(2025, 1, 6, 19, 0)      // outside it

    private func freshDefaults() -> UserDefaults {
        let name = "uninstall-enforcer-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// Wires an enforcer whose stores all read from one isolated defaults suite,
    /// pre-seeded with the given snapshots and opt-in flag.
    private func makeEnforcer(
        snapshots: [RuleSnapshot], enabled: Bool, shields: MockShieldController
    ) -> UninstallProtectionEnforcer {
        let defaults = freshDefaults()
        defaults.set(enabled, forKey: AppGroup.uninstallProtectionKey)
        let store = RuleSnapshotStore(defaults: defaults)
        store.save(snapshots)
        return UninstallProtectionEnforcer(
            snapshots: store, shields: shields,
            ledger: UsageLedger(defaults: defaults), defaults: defaults)
    }

    private func hardSchedule() -> RuleSnapshot {
        RuleSnapshot(rule: BlockingRule(name: "Locked In", hardMode: true))
    }

    @Test("Denies removal when opted in and a hard rule is actively blocking")
    func deniesWhenEnabledAndHardActive() {
        let shields = MockShieldController()
        let enforcer = makeEnforcer(snapshots: [hardSchedule()], enabled: true, shields: shields)

        enforcer.reconcile(at: mondayDuringWork, calendar: utc)

        #expect(shields.appRemovalDenied)
    }

    @Test("Does not deny when the opt-in is off")
    func doesNotDenyWhenDisabled() {
        let shields = MockShieldController()
        let enforcer = makeEnforcer(snapshots: [hardSchedule()], enabled: false, shields: shields)

        enforcer.reconcile(at: mondayDuringWork, calendar: utc)

        #expect(!shields.appRemovalDenied)
    }

    @Test("A soft rule never denies, even opted in")
    func doesNotDenyForSoftRule() {
        let shields = MockShieldController()
        let soft = RuleSnapshot(rule: BlockingRule(name: "Work Time"))
        let enforcer = makeEnforcer(snapshots: [soft], enabled: true, shields: shields)

        enforcer.reconcile(at: mondayDuringWork, calendar: utc)

        #expect(!shields.appRemovalDenied)
    }

    @Test("Denial lifts once the hard window ends")
    func liftsWhenWindowEnds() {
        let shields = MockShieldController()
        let enforcer = makeEnforcer(snapshots: [hardSchedule()], enabled: true, shields: shields)

        enforcer.reconcile(at: mondayDuringWork, calendar: utc)
        #expect(shields.appRemovalDenied)

        enforcer.reconcile(at: mondayEvening, calendar: utc)
        #expect(!shields.appRemovalDenied)
    }
}
