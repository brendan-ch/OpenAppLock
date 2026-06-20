//
//  OpenAppLockReport.swift
//  OpenAppLockReport
//

import DeviceActivity
import SwiftUI

@main
struct OpenAppLockReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RuleUsageReport()
    }
}
