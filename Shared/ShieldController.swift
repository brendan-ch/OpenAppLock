//
//  ShieldController.swift
//  OpenAppLock
//

import FamilyControls
import Foundation
import ManagedSettings

/// Applies and clears app shields for rules. One implementation talks to
/// ManagedSettings; the mock records calls for tests.
protocol ShieldApplying: AnyObject {
    func applyShield(
        ruleID: UUID, selectionData: Data?, mode: SelectionMode, blockAdultContent: Bool
    )
    /// Clears the shield of a single rule (used by the extensions for day
    /// resets and granted opens).
    func clearShield(ruleID: UUID)
    /// Clears every shield except those for the given rule IDs. Covers rules
    /// that were deleted or expired while the app was not running.
    func clearShields(except activeRuleIDs: Set<UUID>)
    /// Engages or relinquishes the device-wide app-removal denial used by
    /// Uninstall Protection. Independent of per-rule shields: it lives on its
    /// own store so clearing rule shields never disturbs it.
    func setAppRemovalDenied(_ denied: Bool)
}

/// Real shield enforcement via per-rule `ManagedSettingsStore`s. Store names
/// are tracked in the shared app-group defaults (ManagedSettings cannot
/// enumerate stores) so the app and extensions see one consistent set.
final class ManagedSettingsShieldController: ShieldApplying {
    private static let trackedIDsKey = "shieldedRuleIDs"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func applyShield(
        ruleID: UUID, selectionData: Data?, mode: SelectionMode, blockAdultContent: Bool
    ) {
        let store = store(for: ruleID)
        let selection = AppSelectionCodec.decode(selectionData)
        switch mode {
        case .block:
            store.shield.applications =
                selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories =
                selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains =
                selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        case .allowOnly:
            // `.all(except:)` is itself a *shield* directive ("block everything
            // except these"), not a whitelist — it cannot lift another store's
            // shield on a shared app. So an Allow-Only rule never punches a hole
            // through a block another rule applies (strictest wins — see
            // `RuleEnforcer`).
            store.shield.applicationCategories = .all(except: selection.applicationTokens)
            store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
        }
        // Screen Time's "Limit Adult Websites" filter for the rule's lifetime.
        store.webContent.blockedByFilter = blockAdultContent ? .auto() : nil
        track(ruleID: ruleID)
        Diag.log(
            .shield, .event,
            "apply rule-\(ruleID.uuidString.prefix(8)) mode=\(mode) adult=\(blockAdultContent) selCount=\(AppSelectionCodec.count(of: selection))")
    }

    func clearShield(ruleID: UUID) {
        Diag.log(.shield, .event, "clear rule-\(ruleID.uuidString.prefix(8))")
        store(for: ruleID).clearAllSettings()
        untrack(ruleID: ruleID)
    }

    func clearShields(except activeRuleIDs: Set<UUID>) {
        let toClear = trackedIDs.subtracting(activeRuleIDs)
        if !toClear.isEmpty {
            Diag.log(
                .shield,
                "clearShields: \(activeRuleIDs.count) active, clearing \(toClear.count) stray")
        }
        for ruleID in toClear {
            clearShield(ruleID: ruleID)
        }
    }

    func setAppRemovalDenied(_ denied: Bool) {
        // A dedicated store keeps this device-wide setting off the per-rule
        // stores, which get fully cleared when their shield lifts. Setting nil
        // (not false) relinquishes the constraint entirely when off.
        let store = ManagedSettingsStore(named: Self.uninstallProtectionStoreName)
        store.application.denyAppRemoval = denied ? true : nil
        if denied { Diag.log(.shield, "appRemovalDenied engaged (Uninstall Protection)") }
    }

    private static let uninstallProtectionStoreName =
        ManagedSettingsStore.Name("uninstall-protection")

    private func store(for ruleID: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("rule-\(ruleID.uuidString)"))
    }

    private var trackedIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: Self.trackedIDsKey) ?? []).compactMap(UUID.init))
    }

    private func track(ruleID: UUID) {
        let ids = trackedIDs.union([ruleID])
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.trackedIDsKey)
    }

    private func untrack(ruleID: UUID) {
        let ids = trackedIDs.subtracting([ruleID])
        defaults.set(ids.map(\.uuidString).sorted(), forKey: Self.trackedIDsKey)
    }
}

/// Records shield operations without touching the system. Used by tests and
/// UI-test launches.
final class MockShieldController: ShieldApplying {
    private(set) var shieldedRuleIDs: Set<UUID> = []
    private(set) var appliedModes: [UUID: SelectionMode] = [:]
    private(set) var appliedAdultContentFlags: [UUID: Bool] = [:]
    private(set) var appliedSelectionData: [UUID: Data?] = [:]
    /// The device-wide app-removal denial. Deliberately separate from the
    /// per-rule shield bookkeeping, mirroring the dedicated store in the real
    /// controller — `clearShields(except:)` must not disturb it.
    private(set) var appRemovalDenied = false

    func applyShield(
        ruleID: UUID, selectionData: Data?, mode: SelectionMode, blockAdultContent: Bool
    ) {
        shieldedRuleIDs.insert(ruleID)
        appliedModes[ruleID] = mode
        appliedAdultContentFlags[ruleID] = blockAdultContent
        appliedSelectionData[ruleID] = selectionData
    }

    func clearShield(ruleID: UUID) {
        shieldedRuleIDs.remove(ruleID)
        appliedModes[ruleID] = nil
        appliedAdultContentFlags[ruleID] = nil
        appliedSelectionData[ruleID] = nil
    }

    func clearShields(except activeRuleIDs: Set<UUID>) {
        shieldedRuleIDs.formIntersection(activeRuleIDs)
        appliedModes = appliedModes.filter { activeRuleIDs.contains($0.key) }
        appliedAdultContentFlags = appliedAdultContentFlags.filter {
            activeRuleIDs.contains($0.key)
        }
        appliedSelectionData = appliedSelectionData.filter { activeRuleIDs.contains($0.key) }
        // Note: appRemovalDenied is intentionally left untouched here.
    }

    func setAppRemovalDenied(_ denied: Bool) {
        appRemovalDenied = denied
    }
}

/// Encodes/decodes `FamilyActivitySelection` for persistence on the rule model.
enum AppSelectionCodec {
    static func encode(_ selection: FamilyActivitySelection) -> Data? {
        try? JSONEncoder().encode(selection)
    }

    static func decode(_ data: Data?) -> FamilyActivitySelection {
        guard let data,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func count(of selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }
}
