//
//  RuleUsageReportView.swift
//  OpenAppLockReport
//

import SwiftUI

/// The rule's usage as drawn inside the report extension and shown on the
/// detail-sheet's full "Usage" page: today's total as a header, then one row per
/// app — "name … flexible gap … duration", heaviest-first. The flexible `Spacer`
/// lets the gap track the row width; the name truncates so it never pushes the
/// duration off-screen, and the durations are monospaced so they line up as a
/// column. A `ScrollView` so a rule with many apps scrolls rather than clipping
/// (a `DeviceActivityReport` can't report its content height to the host). Just
/// the total when there are no per-app rows (i.e. no usage at all).
struct RuleUsageReportView: View {
    let data: RuleUsageReportData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(data.total)
                    .font(.title3.weight(.semibold))
                ForEach(data.apps) { app in
                    HStack(spacing: 8) {
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(app.durationLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
