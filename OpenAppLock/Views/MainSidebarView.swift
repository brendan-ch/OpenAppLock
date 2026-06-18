//
//  MainSidebarView.swift
//  OpenAppLock
//

import SwiftUI

/// The regular-width (full-screen iPad) layout: a persistent left sidebar listing
/// the top-level sections, with the selected section filling the detail column.
///
/// Reuses the exact same section views as the compact `TabView` (`HomeView`,
/// `RulesListView`, `SettingsView` — each brings its own `NavigationStack`); only
/// the navigation chrome differs. Sidebar rows are built from `AppSection`, the
/// shared source of truth, so labels and icons match the tab bar.
struct MainSidebarView: View {
    @State private var selection: AppSection? = .home

    var body: some View {
        // Pin the sidebar visible: on the roomy iPad canvas the top-level
        // sections should always be in reach (HIG), and a constant column
        // visibility keeps the layout stable for UI tests and rotation.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        // Collapse the icon + title into one queryable, hittable
                        // element so UI tests target the row, not the bare symbol.
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("sidebarItem-\(section.rawValue)")
                        .tag(section)
                }
            }
            .navigationTitle("OpenAppLock")
        } detail: {
            detail(for: selection ?? .home)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .home:
            HomeView()
        case .rules:
            RulesListView()
        case .settings:
            SettingsView()
        }
    }
}
