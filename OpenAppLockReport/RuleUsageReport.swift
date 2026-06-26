//
//  RuleUsageReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

/// Renders the filtered rule's combined foreground usage for today. The host
/// (`RuleDetailSheet`) scopes the data via the report's filter, so this scene
/// stays identity-agnostic and never reads the app group. Runs only while the
/// host app foregrounds a `DeviceActivityReport(.ruleUsage, …)`.
struct RuleUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .ruleUsage
    let content: (String) -> Text = { Text($0) }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> String {
        var seconds = 0.0
        for await segment in data.flatMap(\.activitySegments) {
            for await category in segment.categories {
                for await app in category.applications {
                    seconds += app.totalActivityDuration
                }
            }
        }
        return UsageReportFormatter.todayTotal(seconds: seconds)
    }
}
