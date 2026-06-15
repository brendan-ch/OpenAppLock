//
//  RulesListView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Rules tab: every rule, grouped into Schedule / Time Limit / Open Limit
/// sections. "+" creates a new rule; tapping a row opens its detail sheet.
struct RulesListView: View {
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]

    @State private var detailRule: BlockingRule?
    @State private var showingNewRule = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                rulesList(now: timeline.date)
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Rule", systemImage: "plus") {
                        showingNewRule = true
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
    }

    @ViewBuilder
    private func rulesList(now: Date) -> some View {
        if rules.isEmpty {
            ContentUnavailableView {
                Label("No Rules Yet", systemImage: "shield.lefthalf.filled")
            } description: {
                // The identifier lives on the description (not the container),
                // so it surfaces as its own element rather than collapsing onto
                // the action button.
                Text("Create a rule to block distracting apps on a schedule.")
                    .accessibilityIdentifier("emptyRulesCard")
            } actions: {
                Button("New Rule") {
                    showingNewRule = true
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
        let status = rule.status(at: now, usage: enforcer.usage(for: rule, at: now))
        return Button {
            detailRule = rule
        } label: {
            HStack {
                Image(systemName: rule.kind.symbolName)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    Text(blockSummary(for: rule))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Text(rule.statusLabel(for: status, relativeTo: now))
                    .font(.subheadline)
                    .foregroundStyle(status.isActive ? .green : .secondary)
                    .accessibilityIdentifier("ruleStatus-\(rule.name)")
            }
        }
        .accessibilityIdentifier("ruleCard-\(rule.name)")
    }

    private func blockSummary(for rule: BlockingRule) -> String {
        "\(rule.selectionMode.displayName) · \(rule.appList?.name ?? "No apps")"
    }
}
