//
//  MainTabView.swift
//  OpenAppLock
//

import SwiftUI

/// The compact-width layout: the three top-level sections as a bottom `TabView`.
/// Used on iPhone and in iPad multitasking / Slide Over (anywhere the horizontal
/// size class is compact). The app-level enforcement lifecycle lives on the
/// adaptive shell `MainView`, not here, so it runs regardless of layout.
///
/// Tab labels and icons come from `AppSection`, the same source the regular-width
/// sidebar (`MainSidebarView`) uses, so the two layouts can never drift.
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.systemImage) }
            RulesListView()
                .tabItem { Label(AppSection.rules.title, systemImage: AppSection.rules.systemImage) }
            SettingsView()
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
        }
    }
}
