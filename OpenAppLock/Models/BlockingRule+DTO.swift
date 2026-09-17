//
//  BlockingRule+DTO.swift
//  OpenAppLock
//

import FamilyControls
import Foundation

extension BlockingRule {
    /// The rule's selected app lists, ordered like the library and the editor's
    /// picker: name (localized, case-insensitive), creation date breaking ties
    /// (see `AppList.displayOrder`). Relationship order is unspecified, so every
    /// consumer goes through this.
    var sortedAppLists: [AppList] {
        appLists.sorted { first, second in
            let comparison = first.name.localizedStandardCompare(second.name)
            if comparison == .orderedSame {
                return first.createdAt < second.createdAt
            }
            return comparison == .orderedAscending
        }
    }

    /// The union of every selected list's app/category/web-domain tokens, as one
    /// selection — enforcement treats all selected lists as a single app list.
    /// With at most one list carrying data, that list's bytes pass through
    /// unchanged so single-list rules stay byte-identical to the pre-V3 format.
    ///
    /// A true multi-list union requires real Screen Time tokens (decodable only
    /// with Family Controls authorization), so its union is device-verifiable
    /// only; in tests bogus bytes decode to an empty selection.
    var combinedSelectionData: Data? {
        let carriers = appLists.compactMap(\.selectionData)
        if carriers.count <= 1 { return carriers.first }

        var combined = FamilyActivitySelection()
        for data in carriers {
            let selection = AppSelectionCodec.decode(data)
            combined.applicationTokens.formUnion(selection.applicationTokens)
            combined.categoryTokens.formUnion(selection.categoryTokens)
            combined.webDomainTokens.formUnion(selection.webDomainTokens)
        }
        if combined.applicationTokens.isEmpty
            && combined.categoryTokens.isEmpty
            && combined.webDomainTokens.isEmpty {
            Diag.log(
                .rule, .event,
                "multi-list combined selection decoded empty (opportunistic union on device; bogus bytes or no authorization here)")
            return nil
        }
        return AppSelectionCodec.encode(combined)
    }

    /// The app-level summary for the rule's projected selection: a single list
    /// shows "name · N Apps"; multiple lists show "N Lists · M Apps"; no lists
    /// (or none selected) shows the no-apps placeholder.
    var appListSummary: String {
        let lists = sortedAppLists
        if lists.isEmpty { return CopyKey.ruleDetailNoAppsPlaceholder.string }
        if let only = lists.first, lists.count == 1 {
            return CopyKey.ruleDetailAppListSummaryFormat.string(only.name, only.appCountLabel)
        }
        let apps = lists.reduce(0) { $0 + $1.selectionCount }
        return CopyKey.ruleEditorAppListMultipleSummaryFormat.string(lists.count, apps)
    }
}

extension RuleSnapshotDTO {
    /// Builds the projection from a `BlockingRule`, flattening the app-list
    /// relationships to their union `selectionData` (see `combinedSelectionData`).
    /// The canonical call site is `BlockingRule.dto`; this initializer is its
    /// implementation.
    init(rule: BlockingRule) {
        self.init(
            id: rule.id,
            name: rule.name,
            kindRaw: rule.kindRaw,
            isEnabled: rule.isEnabled,
            hardMode: rule.hardMode,
            selectionModeRaw: rule.selectionModeRaw,
            selectionData: rule.combinedSelectionData,
            dayNumbers: rule.dayNumbers,
            startMinutes: rule.startMinutes,
            endMinutes: rule.endMinutes,
            dailyLimitMinutes: rule.dailyLimitMinutes,
            maxOpens: rule.maxOpens,
            pausedUntil: rule.pausedUntil)
    }
}

extension BlockingRule {
    /// The Codable projection of this rule. This is the single conversion point
    /// from the SwiftData `@Model` to the value type every consumer outside the
    /// store, the rule editors, and the mutation path speaks.
    var dto: RuleSnapshotDTO { RuleSnapshotDTO(rule: self) }
}
