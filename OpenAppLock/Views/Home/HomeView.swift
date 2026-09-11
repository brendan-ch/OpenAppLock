//
//  HomeView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Home tab: what's blocking right now, plus the rules armed for today
/// ("Active Rules"). Rows in each section are alphabetical by name (see
/// `BlockingRule.displayOrder`). The rule list and rule creation live on the
/// Rules tab.
struct HomeView: View {
    @Environment(\.capturedURL) private var capturedURL
    @Environment(\.captureURL) private var captureURL
    @Environment(RuleEnforcer.self) private var enforcer
    @AppStorage(AppGroup.migrationDataChangedKey, store: AppGroup.defaults) private var migrationDataChanged: Bool = false
    @AppStorage(AppGroup.migrationBannerDismissedKey, store: AppGroup.defaults) private var shouldDismissMigrationBanner: Bool = false
    @Query(sort: BlockingRule.displayOrder) private var rules: [BlockingRule]
    
    @State private var detailRule: BlockingRule?
    @State private var viewAppeared = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                homeList(now: timeline.date)
            }
            .navigationTitle(CopyKey.homeNavigationTitle.resource)
        }
        .sheet(item: $detailRule) { rule in
            RuleDetailSheet(rule: rule)
        }
        .onAppear {
            viewAppeared = true
        }
        .onDisappear {
            viewAppeared = false
        }
        .onChange(of: capturedURL) {
            tryCaptureURLIfViewAppeared()
        }
        .onChange(of: viewAppeared) {
            tryCaptureURLIfViewAppeared()
        }
    }

    private func homeList(now: Date) -> some View {
        List {
            blockingSection(now: now)
            activeRulesSection(now: now)
            bannersSection()
        }
    }

    /// Status with the day's usage folded in, so limit rules whose budget is
    /// spent count as actively blocking.
    private func liveStatus(for rule: BlockingRule, now: Date) -> RuleStatus {
        let dto = rule.dto
        return dto.status(at: now, usage: enforcer.usage(for: dto, at: now))
    }
    
    // MARK: - State setters
    
    private func tryCaptureURLIfViewAppeared() {
        if viewAppeared {
            if let capturedURL = capturedURL {
                detailRule = URLResolver.resolveRule(from: capturedURL, in: rules)
                captureURL()
            }
        }
    }
    
    // MARK: - Currently Blocking

    @ViewBuilder
    private func blockingSection(now: Date) -> some View {
        let blocking = rules.filter { liveStatus(for: $0, now: now).isActive }
        Section {
            if blocking.isEmpty {
                Text(.homeNothingBlockingMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nothingBlockedLabel")
            } else {
                ForEach(blocking) { rule in
                    blockingRow(for: rule, now: now)
                }
            }
        } header: {
            Text(.homeCurrentlyBlockingSectionHeader).textCase(nil)
        }
    }

    /// A blocking rule: leading kind icon, name, and a "<Type> · <context>"
    /// subtitle (a schedule shows its countdown, a limit its usage). Tapping
    /// opens the rule's detail overlay, where Pause/Resume (for supported soft
    /// rules) lives.
    private func blockingRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsageDTO()
        let status = liveStatus(for: rule, now: now)
        return Button {
            detailRule = rule
        } label: {
            HStack {
                kindIcon(for: rule)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("blockedTile-\(rule.name)")
    }

    /// The rule's kind icon, tinted, sized to align row text. Decorative — the
    /// type is also spelled out in the subtitle, so it is hidden from VoiceOver.
    private func kindIcon(for rule: BlockingRule) -> some View {
        Image(systemName: rule.kind.symbolName)
            .foregroundStyle(.tint)
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Active Rules

    /// Enabled rules that aren't currently blocking but are armed for today:
    /// limit rules scheduled today (showing their budget) and schedule rules
    /// whose next window starts within 24h (showing their next-start). Tapping a
    /// row opens the rule's detail overlay.
    @ViewBuilder
    private func activeRulesSection(now: Date) -> some View {
        let active = rules.filter {
            $0.dto.belongsInActiveRules(at: now, usage: enforcer.usage(for: $0.dto, at: now))
        }
        if !active.isEmpty {
            Section {
                ForEach(active) { rule in
                    activeRuleRow(for: rule, now: now)
                }
            } header: {
                Text(.homeActiveRulesSectionHeader).textCase(nil)
            }
        }
    }

    private func activeRuleRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsageDTO()
        let status = liveStatus(for: rule, now: now)
        return Button {
            detailRule = rule
        } label: {
            HStack {
                kindIcon(for: rule)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("activeRuleRow-\(rule.name)")
    }
    
    // MARK: - Banners

    @ViewBuilder
    private func bannersSection() -> some View {
        // May split out into a dedicated banner system later, don't want to over-engineer right now
        Section {
            if !shouldDismissMigrationBanner && migrationDataChanged {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Some of your data was migrated")
                            .bold()
                        Text("Start and end times for your Schedule rules have shifted to support rule blocking improvements.")
                        
                        Spacer().frame(height: 4)
                        
                        HStack(spacing: 24) {
                            Button {
                                withAnimation {
                                    shouldDismissMigrationBanner = true
                                }
                            } label: {
                                Text("Dismiss")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("dismissMigrationBannerButton")
                        }
                    }
                    Spacer()
                }
                .accessibilityIdentifier("migrationBanner")
            }
        }
        
    }
}

#if DEBUG
/// Seeds the standard Home state via `SampleRules`: the active soft rule
/// "Work Time" (Currently Blocking, pausable) and the upcoming "Sleep" (Active
/// Rules), so the preview exercises both sections with live status rows.
@MainActor
private func homePreview() -> some View {
    let container = try! ModelContainer(
        for: BlockingRule.self, AppList.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    SampleRules.seed(.standard, into: container.mainContext)
    return HomeView()
        .modelContainer(container)
        .environment(RuleEnforcer(shields: MockShieldController()))
}

#Preview("Active window + upcoming") {
    homePreview()
}
#endif
