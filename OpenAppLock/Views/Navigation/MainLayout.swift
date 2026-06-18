//
//  MainLayout.swift
//  OpenAppLock
//

import SwiftUI

/// Which navigation chrome the post-onboarding shell shows, chosen from the
/// horizontal size class: a left sidebar on the roomy regular-width iPad canvas,
/// the bottom tab bar everywhere else (iPhone, plus iPad multitasking / Slide
/// Over, where the width is compact).
enum MainLayout {
    case tabs
    case sidebar

    /// Resolves the layout from the current horizontal size class. The sidebar is
    /// reserved for *known* regular width; an undetermined (`nil`) size class
    /// falls back to the iPhone-safe tab bar.
    static func resolve(horizontalSizeClass: UserInterfaceSizeClass?) -> MainLayout {
        horizontalSizeClass == .regular ? .sidebar : .tabs
    }
}
