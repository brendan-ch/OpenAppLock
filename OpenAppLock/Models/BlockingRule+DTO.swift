//
//  BlockingRule+DTO.swift
//  OpenAppLock
//

import FamilyControls
import Foundation

extension BlockingRule {
    var sortedAppLists: [AppList] {
        appLists.sorted { first, second in
            let comparison = first.name.localizedStandardCompare(second.name)
            if comparison == .orderedSame {
                return first.createdAt < second.createdAt
            }
            return comparison == .orderedAscending
        }
    }

    /// Union of every selected list, as one selection. ≤ 1 data-carrying list
    /// passes through byte-identical to the pre-V3 format.
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
                "multi-list combined selection decoded empty (bogus bytes or no authorization here)")
            return nil
        }
        return AppSelectionCodec.encode(combined)
    }

    /// Single list: "name · N Apps"; several: "N Lists · M Apps"; none: "No apps".
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
    /// Builds the projection from a `BlockingRule`; uses the union selection.
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
