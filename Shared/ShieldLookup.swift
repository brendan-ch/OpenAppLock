//
//  ShieldLookup.swift
//  OpenAppLock
//

import FamilyControls
import Foundation
import ManagedSettings

/// Matches shielded tokens back to the rule that shields them, so the shield
/// UI can offer "Open" with the right counts for open-limit rules.
enum ShieldLookup {
    static func openLimitSnapshot(
        containingApplication token: ApplicationToken, in snapshots: [RuleSnapshot]
    ) -> RuleSnapshot? {
        snapshots.first { snapshot in
            guard snapshot.kind == .openLimit, snapshot.isEnabled else { return false }
            return AppSelectionCodec.decode(snapshot.selectionData)
                .applicationTokens.contains(token)
        }
    }

    static func openLimitSnapshot(
        containingCategory token: ActivityCategoryToken, in snapshots: [RuleSnapshot]
    ) -> RuleSnapshot? {
        snapshots.first { snapshot in
            guard snapshot.kind == .openLimit, snapshot.isEnabled else { return false }
            return AppSelectionCodec.decode(snapshot.selectionData)
                .categoryTokens.contains(token)
        }
    }
}
