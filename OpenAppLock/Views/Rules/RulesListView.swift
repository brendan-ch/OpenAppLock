//
//  RulesListView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Rules tab: every rule, grouped into Schedule / Time Limit / Open Limit
/// sections, alphabetical by name within each section (see
/// `BlockingRule.displayOrder`). "+" creates a new rule; tapping a row opens its
/// detail sheet.
struct RulesListView: View {
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: BlockingRule.displayOrder) private var rules: [BlockingRule]

    @State private var detailRule: BlockingRule?
    @State private var showingNewRule = false
    @State private var showingRuleLimitAlert = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                rulesList(now: timeline.date)
            }
            .navigationTitle(CopyKey.rulesListNavigationTitle.resource)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CopyKey.rulesListNewRuleButton.resource, systemImage: "plus") {
                        attemptNewRule()
                    }
                    .accessibilityIdentifier("newRuleButton")
                }
            }
        }
        .sheet(item: $detailRule) { rule in
            RuleDetailSheet(rule: rule)
        }
        .sheet(isPresented: $showingNewRule) {
            NewRuleSheet()
        }
        .alert(
            Text(CopyKey.rulesListRuleLimitAlertTitle.resource),
            isPresented: $showingRuleLimitAlert
        ) {
            Button(CopyKey.appListsOkButtonLabel.resource, role: .cancel) {}
        } message: {
            Text(CopyKey.rulesListRuleLimitAlertMessage.string(RuleCreationPolicy.maxRuleCount))
        }
    }

    /// Presents the New Rule sheet, or the cap alert when the rule limit is
    /// reached (see `RuleCreationPolicy`). Both the toolbar and empty-state
    /// buttons route through here.
    private func attemptNewRule() {
        if RuleCreationPolicy.canCreateRule(existingRuleCount: rules.count) {
            showingNewRule = true
        } else {
            showingRuleLimitAlert = true
        }
    }

    @ViewBuilder
    private func rulesList(now: Date) -> some View {
        if rules.isEmpty {
            ContentUnavailableView {
                Label(CopyKey.rulesListNoRulesYetTitle.resource, systemImage: "shield.lefthalf.filled")
            } description: {
                // The identifier lives on the description (not the container),
                // so it surfaces as its own element rather than collapsing onto
                // the action button.
                Text(.rulesListEmptyStateDescription)
                    .accessibilityIdentifier("emptyRulesCard")
            } actions: {
                Button(CopyKey.rulesListNewRuleButton.resource) {
                    attemptNewRule()
                }
                .accessibilityIdentifier("emptyStateNewRuleButton")
            }
        } else {
            List {
                kindSection(.schedule, now: now)
                kindSection(.timeLimit, now: now)
                kindSection(.openLimit, now: now)
            }
        }
    }

    /// One section per rule kind; empty kinds are omitted entirely.
    @ViewBuilder
    private func kindSection(_ kind: RuleKind, now: Date) -> some View {
        let kindRules = rules.filter { $0.kind == kind }
        if !kindRules.isEmpty {
            Section {
                ForEach(kindRules) { rule in
                    ruleRow(for: rule, now: now)
                }
            } header: {
                Text(kind.displayName).textCase(nil)
            }
        }
    }

    private func ruleRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsageDTO()
        let status = dto.status(at: now, usage: usage)
        return Button {
            detailRule = rule
        } label: {
            HStack {
                Image(systemName: rule.kind.symbolName)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    // The kind is conveyed by the section header, so the
                    // subtitle is just the live context (no type prefix).
                    Text(dto.rowContext(for: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("ruleStatus-\(rule.name)")
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("ruleCard-\(rule.name)")
    }
}

#if DEBUG
/// Seeds several rules per kind, inserted **out of** alphabetical order, so the
/// preview demonstrates each section sorting alphabetically by name regardless
/// of creation order (see `BlockingRule.displayOrder`).
@MainActor
private func rulesListOrderingPreview() -> some View {
    let container = try! ModelContainer(
        for: BlockingRule.self, AppList.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    // Within each kind the insertion order is deliberately not alphabetical.
    let seeds: [(String, RuleConfiguration)] = [
        ("Wind Down", .schedule(ScheduleConfig(startMinutes: 22 * 60, endMinutes: 6 * 60))),
        ("Bedtime", .schedule(ScheduleConfig(startMinutes: 23 * 60, endMinutes: 7 * 60))),
        ("Morning Focus", .schedule(ScheduleConfig(startMinutes: 8 * 60, endMinutes: 9 * 60))),
        ("Time Keeper", .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45))),
        ("Doom Scroll", .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30))),
        ("Social Cap", .openLimit(OpenLimitConfig(maxOpens: 5))),
        ("Games", .openLimit(OpenLimitConfig(maxOpens: 3))),
    ]
    for (name, configuration) in seeds {
        container.mainContext.insert(
            BlockingRule(name: name, configuration: configuration, days: Weekday.everyDay))
    }
    return RulesListView()
        .modelContainer(container)
        .environment(RuleEnforcer(shields: MockShieldController()))
}

#Preview("Alphabetical within each kind") {
    rulesListOrderingPreview()
}
#endif
