//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Renders the filtered rule's usage for today — a combined total plus a per-app
/// breakdown. The host (`RuleDetailSheet`, time-limit rules only) scopes the data
/// via the report's filter, so this scene stays identity-agnostic and never reads
/// the app group. Runs only while the host app foregrounds a
/// `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (RuleUsageReportData) -> RuleUsageReportView = { RuleUsageReportView(data: $0) }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> RuleUsageReportData {
        // Emit one (name, seconds) per app activity; `report` sums entries that
        // share a display name (the same app across segments/categories) into one
        // row, so this loop stays a flat collection.
        var apps: [(name: String, seconds: Double)] = []
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName
                        ?? app.application.bundleIdentifier
                        ?? CopyKey.usageReportUnknownAppName.string
                    apps.append((name, app.totalActivityDuration))
                }
            }
        }
        return UsageReportFormatter.report(apps: apps)
    }
}
