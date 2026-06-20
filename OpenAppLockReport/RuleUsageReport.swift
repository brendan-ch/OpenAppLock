//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Recomputes authoritative daily usage for time-limit rules as a side effect of
/// rendering. The view is intentionally empty — the app consumes the ledger
/// write, not the view. Runs only while the host app foregrounds a
/// `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (Int) -> EmptyView = { _ in EmptyView() }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> Int {
        await RuleUsageReportWriter().write(from: data)
        return 0
    }
}
