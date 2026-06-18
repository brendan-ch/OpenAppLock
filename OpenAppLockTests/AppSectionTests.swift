//
//  AppSectionTests.swift
//  OpenAppLockTests
//

import Testing
@testable import OpenAppLock

/// `AppSection` is the single source of truth for the top-level sections, shared
/// by the compact `TabView` (`MainTabView`) and the regular-width sidebar
/// (`MainSidebarView`). These tests pin its order, labels, and icons so the two
/// layouts can never drift.
@MainActor
struct AppSectionTests {
    @Test("Sections are ordered Home, Rules, Settings")
    func ordering() {
        #expect(AppSection.allCases == [.home, .rules, .settings])
    }

    @Test("There are exactly three top-level sections")
    func count() {
        #expect(AppSection.allCases.count == 3)
    }

    @Test("Each section exposes its display title")
    func titles() {
        #expect(AppSection.home.title == "Home")
        #expect(AppSection.rules.title == "Rules")
        #expect(AppSection.settings.title == "Settings")
    }

    @Test("Each section exposes its SF Symbol")
    func symbols() {
        #expect(AppSection.home.systemImage == "house")
        #expect(AppSection.rules.systemImage == "shield.lefthalf.filled")
        #expect(AppSection.settings.systemImage == "gearshape")
    }

    @Test("Identifiers are the stable raw values")
    func identifiers() {
        #expect(AppSection.home.id == "home")
        #expect(AppSection.rules.id == "rules")
        #expect(AppSection.settings.id == "settings")
    }
}
