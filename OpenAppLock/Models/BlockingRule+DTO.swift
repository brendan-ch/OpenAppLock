//
//  BlockingRule+DTO.swift
//  OpenAppLock
//

import Foundation

extension RuleSnapshotDTO {
    /// Builds the projection from a `BlockingRule`, flattening the app-list
    /// relationship to its raw `selectionData`. The canonical call site is
    /// `BlockingRule.dto`; this initializer is its implementation.
    init(rule: BlockingRule) {
        self.init(
            id: rule.id,
            name: rule.name,
            kindRaw: rule.kindRaw,
            isEnabled: rule.isEnabled,
            hardMode: rule.hardMode,
            selectionModeRaw: rule.selectionModeRaw,
            selectionData: rule.appList?.selectionData,
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
