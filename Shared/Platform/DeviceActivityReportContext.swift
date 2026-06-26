//
//  DeviceActivityReportContext.swift
//  OpenAppLock
//

import DeviceActivity
import SwiftUI

extension DeviceActivityReport.Context {
    /// The report scene that renders a rule's combined foreground usage for
    /// today. Shared so the host app and the report extension name it the same.
    static let ruleUsage = Self("Rule Usage")
}
