//
//  MainLayoutTests.swift
//  OpenAppLockTests
//

import SwiftUI
import Testing
@testable import OpenAppLock

/// `MainLayout.resolve` decides whether the post-onboarding shell shows the
/// bottom `TabView` or the left sidebar, purely from the horizontal size class.
/// Sidebar is reserved for *known* regular width so an undetermined size class
/// falls back to the iPhone-safe tab bar.
@MainActor
struct MainLayoutTests {
    @Test("Regular width uses the sidebar")
    func regularUsesSidebar() {
        #expect(MainLayout.resolve(horizontalSizeClass: .regular) == .sidebar)
    }

    @Test("Compact width uses tabs")
    func compactUsesTabs() {
        #expect(MainLayout.resolve(horizontalSizeClass: .compact) == .tabs)
    }

    @Test("Unknown width falls back to tabs")
    func unknownFallsBackToTabs() {
        #expect(MainLayout.resolve(horizontalSizeClass: nil) == .tabs)
    }
}
