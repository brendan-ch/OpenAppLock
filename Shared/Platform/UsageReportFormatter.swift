//
//  UsageReportFormatter.swift
//  OpenAppLock
//

import Foundation

/// Formats a day's foreground-usage total for the rule-detail report view.
/// Pure and Shared so the report extension can render it and unit tests can
/// cover it. Returns an empty string under one minute — the report's blank state.
nonisolated enum UsageReportFormatter {
    static func todayTotal(seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        guard minutes > 0 else { return "No usage today" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 && remainder > 0 { return "\(hours)h \(remainder)m today" }
        if hours > 0 { return "\(hours)h today" }
        return "\(remainder)m today"
    }
}
