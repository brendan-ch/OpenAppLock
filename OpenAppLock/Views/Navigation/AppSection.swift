//
//  AppSection.swift
//  OpenAppLock
//

import Foundation

/// The app's top-level sections. Single source of truth for the post-onboarding
/// navigation, shared by the compact `TabView` (`MainTabView`) and the
/// regular-width sidebar (`MainSidebarView`) so the two layouts can't drift.
enum AppSection: String, CaseIterable, Identifiable {
    case home
    case rules
    case settings

    var id: String { rawValue }

    /// User-facing label shown in the tab item and the sidebar row.
    var title: String {
        switch self {
        case .home: CopyKey.navHomeSectionTitle.string
        case .rules: CopyKey.navRulesSectionTitle.string
        case .settings: CopyKey.navSettingsSectionTitle.string
        }
    }

    /// SF Symbol shown alongside the title in both layouts.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .rules: "shield.lefthalf.filled"
        case .settings: "gearshape"
        }
    }
}
