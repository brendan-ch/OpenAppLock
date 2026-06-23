//
//  MainView.swift
//  OpenAppLock
//

import DeviceActivity
import FamilyControls
import ManagedSettings
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
            .background(ruleUsageReport)
            .task {
                await enforcementLoop()
            }
            .onChange(of: ruleChangeToken) {
                // Logs the rule/app-list-driven refresh trigger so the timeline
                // shows whether (e.g.) an app-list edit re-enforced at all.
                Diag.log(.lifecycle, "refresh trigger: rule-change observed")
                refreshEnforcement()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Diag.log(.lifecycle, "refresh trigger: scenePhase active")
                    refreshEnforcement()
                }
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

    // MARK: - Authoritative usage report

    /// An invisible `DeviceActivityReport` so the report extension recomputes
    /// each time-limit rule's true daily usage whenever the app is foreground;
    /// the 30 s refresh loop then reads the authoritative totals it writes.
    private var ruleUsageReport: some View {
        DeviceActivityReport(.ruleUsage, filter: usageFilter)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// Today's `.daily` filter over the union of all enabled time-limit rules'
    /// selections — the data the report scene attributes back to each rule.
    private var usageFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let interval = DateInterval(start: calendar.startOfDay(for: .now), end: .now)
        var applications: Set<ApplicationToken> = []
        var categories: Set<ActivityCategoryToken> = []
        var webDomains: Set<WebDomainToken> = []
        for rule in rules where rule.kind == .timeLimit && rule.isEnabled {
            let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
            applications.formUnion(selection.applicationTokens)
            categories.formUnion(selection.categoryTokens)
            webDomains.formUnion(selection.webDomainTokens)
        }
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: applications,
            categories: categories,
            webDomains: webDomains)
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
            // The 30 s foreground backstop. Logged each tick so coverage gaps
            // (when the app isn't open to run this) are visible as timeline holes.
            Diag.log(.lifecycle, "refresh trigger: foreground 30s loop")
            enforcer.refresh(rules: allRules)
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
