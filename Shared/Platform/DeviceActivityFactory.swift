//
//  DeviceActivityFactory.swift
//  OpenAppLock
//

import DeviceActivity
import FamilyControls
import Foundation

/// Shared DeviceActivity construction so the app scheduler and the background
/// extensions that also start activities directly can't drift.
nonisolated enum DeviceActivityFactory {
    /// A non-repeating schedule spanning `start`...`end` wall-clock.
    static func nonRepeatingSchedule(
        from start: Date, to end: Date, calendar: Calendar = .current
    ) -> DeviceActivitySchedule {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false)
    }

    /// One `DeviceActivityEvent` per `eventMinutes` entry over `selectionData`,
    /// with `includesPastActivity` so a restart backfills same-interval accrual.
    static func thresholdEvents(
        selectionData: Data?, eventMinutes: [String: Int]
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        let selection = AppSelectionCodec.decode(selectionData)
        return Dictionary(
            uniqueKeysWithValues: eventMinutes.map { name, minutes in
                (
                    DeviceActivityEvent.Name(name),
                    DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: DateComponents(minute: minutes),
                        includesPastActivity: true)
                )
            })
    }
}
