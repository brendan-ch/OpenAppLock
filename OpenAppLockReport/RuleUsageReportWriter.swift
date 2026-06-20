//
//  RuleUsageReportWriter.swift
//  OpenAppLockReport
//

import DeviceActivity
import FamilyControls
import Foundation
import SwiftUI

/// Sums each enabled time-limit rule's true daily usage from Screen Time's own
/// per-application totals and records it as the authoritative figure in the
/// shared ledger. Attribution is by application token; category/web-domain
/// selections are not yet attributed (see spec §9 — confirm on device).
struct RuleUsageReportWriter {
    func write(from data: DeviceActivityResults<DeviceActivityData>, now: Date = Date()) async {
        let snapshots = RuleSnapshotStore().load()
            .filter { $0.kind == .timeLimit && $0.isEnabled }
        guard !snapshots.isEmpty else { return }
        let selections = snapshots.map { ($0, AppSelectionCodec.decode($0.selectionData)) }

        var secondsByRule: [UUID: Double] = [:]
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    guard let token = app.application.token else { continue }
                    let seconds = app.totalActivityDuration
                    for (snapshot, selection) in selections
                    where selection.applicationTokens.contains(token) {
                        secondsByRule[snapshot.id, default: 0] += seconds
                    }
                }
            }
        }

        let ledger = UsageLedger()
        for (snapshot, _) in selections {
            let minutes = Int((secondsByRule[snapshot.id] ?? 0) / 60)
            ledger.recordAuthoritativeMinutes(
                minutes, for: snapshot.id, onDayContaining: now, asOf: now)
        }
    }
}
