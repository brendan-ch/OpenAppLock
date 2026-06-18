//
//  MainView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The post-onboarding shell. Chooses its navigation chrome from the horizontal
/// size class — a bottom `TabView` (`MainTabView`) in compact width (iPhone, iPad
/// multitasking) and a left sidebar (`MainSidebarView`) in regular width
/// (full-screen iPad) — and owns the app-level enforcement lifecycle so it runs
/// regardless of which layout is showing and which section is selected.
///
/// The lifecycle is a 30 s `refresh` loop, a reconcile on any blocking-relevant
/// rule change, and a reconcile whenever the app becomes active (so Uninstall
/// Protection re-evaluates on every foreground).
struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]

    var body: some View {
        layout
            .task {
                await enforcementLoop()
            }
            .onChange(of: ruleChangeToken) {
                refreshEnforcement()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshEnforcement() }
            }
    }

    @ViewBuilder
    private var layout: some View {
        switch MainLayout.resolve(horizontalSizeClass: horizontalSizeClass) {
        case .tabs:
            MainTabView()
        case .sidebar:
            MainSidebarView()
        }
    }

    // MARK: - Enforcement

    /// Changes whenever any rule's blocking-relevant state changes.
    private var ruleChangeToken: String {
        rules.map {
            "\($0.id)|\($0.isEnabled)|\($0.hardMode)|\($0.blockAdultContent)|"
                + "\($0.startMinutes)|\($0.endMinutes)|\($0.dayNumbers)|"
                + "\($0.selectionModeRaw)|\($0.appList?.id.uuidString ?? "-")|"
                + "\($0.appList?.selectionCount ?? 0)|"
                + "\($0.pausedUntil?.timeIntervalSince1970 ?? 0)"
        }
        .joined(separator: ",")
    }

    private func refreshEnforcement() {
        enforcer.refresh(rules: rules)
    }

    /// Keeps shields in sync while the app is open, so windows that begin or end
    /// while the user is looking at the screen take effect promptly.
    private func enforcementLoop() async {
        while !Task.isCancelled {
            let allRules = (try? modelContext.fetch(FetchDescriptor<BlockingRule>())) ?? []
            enforcer.refresh(rules: allRules)
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
