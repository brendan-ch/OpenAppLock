//
//  DeviceActivityReportContext.swift
//  OpenAppLock
//

import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    /// The report scene that recomputes authoritative daily usage for limit
    /// rules. Shared so the host app and the report extension name it the same.
    static let ruleUsage = Self("Rule Usage")
}
