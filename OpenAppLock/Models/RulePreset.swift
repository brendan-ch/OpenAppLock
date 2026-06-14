//
//  RulePreset.swift
//  OpenAppLock
//

import SwiftUI

/// A suggested schedule rule shown in the New Rule sheet's preset gallery.
struct RulePreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let startMinutes: Int
    let endMinutes: Int
    let days: Set<Weekday>
    let symbolName: String
    /// Gradient background shown behind each preset card.
    let gradientTop: Color
    let gradientBottom: Color

    var schedule: RuleSchedule {
        RuleSchedule(startMinutes: startMinutes, endMinutes: endMinutes, days: days)
    }
}

/// A titled group of presets ("Focus Time", "Rest & Recharge", …).
struct RulePresetSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let presets: [RulePreset]

    static let all: [RulePresetSection] = [
        RulePresetSection(
            id: "focus",
            title: "Focus Time",
            subtitle: "Protect your deep-work hours.",
            presets: [
                RulePreset(
                    id: "morning-focus", name: "Morning Focus",
                    startMinutes: 8 * 60, endMinutes: 11 * 60 + 30, days: Weekday.weekdays,
                    symbolName: "sunrise.fill",
                    gradientTop: Color(red: 0.33, green: 0.23, blue: 0.13),
                    gradientBottom: Color(red: 0.12, green: 0.07, blue: 0.03)
                ),
                RulePreset(
                    id: "deep-work", name: "Deep Work",
                    startMinutes: 13 * 60 + 30, endMinutes: 16 * 60, days: Weekday.weekdays,
                    symbolName: "scope",
                    gradientTop: Color(red: 0.13, green: 0.20, blue: 0.33),
                    gradientBottom: Color(red: 0.04, green: 0.06, blue: 0.12)
                ),
            ]
        ),
        RulePresetSection(
            id: "rest",
            title: "Rest & Recharge",
            subtitle: "Wind the day down on schedule.",
            presets: [
                RulePreset(
                    id: "evening-reset", name: "Evening Reset",
                    startMinutes: 21 * 60, endMinutes: 23 * 60, days: Weekday.everyDay,
                    symbolName: "moon.haze.fill",
                    gradientTop: Color(red: 0.25, green: 0.18, blue: 0.33),
                    gradientBottom: Color(red: 0.08, green: 0.05, blue: 0.12)
                ),
                RulePreset(
                    id: "lights-out", name: "Lights Out",
                    startMinutes: 23 * 60, endMinutes: 6 * 60 + 30, days: Weekday.everyDay,
                    symbolName: "moon.zzz.fill",
                    gradientTop: Color(red: 0.10, green: 0.13, blue: 0.30),
                    gradientBottom: Color(red: 0.02, green: 0.03, blue: 0.10)
                ),
            ]
        ),
        RulePresetSection(
            id: "balance",
            title: "Healthy Balance",
            subtitle: "Make room for what matters.",
            presets: [
                RulePreset(
                    id: "family-dinner", name: "Family Dinner",
                    startMinutes: 18 * 60, endMinutes: 19 * 60 + 30, days: Weekday.everyDay,
                    symbolName: "fork.knife",
                    gradientTop: Color(red: 0.16, green: 0.27, blue: 0.22),
                    gradientBottom: Color(red: 0.05, green: 0.10, blue: 0.08)
                ),
                RulePreset(
                    id: "screen-free-sunday", name: "Screen-Free Sunday",
                    startMinutes: 9 * 60, endMinutes: 20 * 60, days: [.sunday],
                    symbolName: "leaf.fill",
                    gradientTop: Color(red: 0.13, green: 0.30, blue: 0.30),
                    gradientBottom: Color(red: 0.03, green: 0.10, blue: 0.10)
                ),
            ]
        ),
    ]
}
