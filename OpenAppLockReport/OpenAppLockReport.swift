//
//  OpenAppLockReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI
import ExtensionKit

@main
struct OpenAppLockReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RuleUsageReport()
    }
}
