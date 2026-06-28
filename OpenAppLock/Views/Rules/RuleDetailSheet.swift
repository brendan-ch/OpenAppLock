//
//  RuleDetailSheet.swift
//  OpenAppLock
//

import DeviceActivity
import FamilyControls
import SwiftData
import SwiftUI

/// Rule summary presented as a plain sheet: inline title with a live status
/// caption, the rule's facts as labeled rows, and "Edit Rule" — which pushes
/// the editor. A hard-locked rule shows a lock notice instead.
struct RuleDetailSheet: View {
    let rule: BlockingRule

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    @State private var isEditing = false
    @State private var pendingDeletion = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                detailList(now: timeline.date)
            }
            .navigationDestination(isPresented: $isEditing) {
                RuleEditorView(
                    mode: .edit(isEnabled: rule.isEnabled),
                    draft: RuleDraft(rule: rule),
                    onCommit: { draft in
                        draft.apply(to: rule)
                        isEditing = false
                    },
                    onToggleEnabled: {
                        rule.isEnabled.toggle()
                        rule.pausedUntil = nil
                        isEditing = false
                    },
                    onDelete: {
                        pendingDeletion = true
                        dismiss()
                    }
                )
            }
        }
        .onDisappear {
            if pendingDeletion {
                modelContext.delete(rule)
            }
        }
    }

    private func detailList(now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now)
        let status = dto.status(at: now, usage: usage)
        return List {
            Section("Details") {
                detailRows
            }
            // Live Screen Time usage for this rule's apps, rendered inside the
            // report extension (the only place the data is available). Gated
            // under UI testing — the system view does not run in the harness —
            // and blank when there is no usage.
            if !LaunchConfiguration.current.isUITesting {
                Section("Usage") {
                    DeviceActivityReport(.ruleUsage, filter: usageFilter)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .accessibilityIdentifier("ruleUsageReport")
                }
            }
            Section {
                if RulePolicy.canEdit(dto, usage: usage, at: now) {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Edit Rule", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("editRuleButton")
                } else {
                    Label(
                        "Hard Mode is on — this rule is locked until the block ends.",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("hardModeLockedNotice")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .accessibilityIdentifier("closeDetailButton")
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(rule.name)
                        .font(.headline)
                        .accessibilityIdentifier("detailRuleName")
                    Text("\(dto.kind.displayName), \(dto.rowContext(for: status, usage: usage ?? RuleUsageDTO(), relativeTo: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("detailStatusLabel")
                }
            }
        }
    }

    /// Today's `.daily` filter scoped to this rule's selection, so the report
    /// extension attributes only this rule's apps/categories/web domains.
    private var usageFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let interval = DateInterval(start: calendar.startOfDay(for: .now), end: .now)
        let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
        return DeviceActivityFilter(
            segment: .daily(during: interval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens)
    }

    @ViewBuilder
    private var detailRows: some View {
        switch rule.configuration {
        case .schedule(let config):
            row("During this time", rule.schedule.timeRangeLabel)
            row("On these days", rule.days.summary)
            row(config.selectionMode.displayName, appCountLabel)
            row("Unblocks allowed", rule.hardMode ? "No" : "Yes")
        case .timeLimit(let config):
            row("When I use", appCountLabel)
            row("For this long", "\(config.dailyLimitMinutes)m daily")
            row("On these days", rule.days.summary)
            row("Then block until", "Tomorrow")
            row("Unblocks allowed", rule.hardMode ? "No" : "Yes")
        case .openLimit(let config):
            row("When I open", appCountLabel)
            row("More than", "\(config.maxOpens) opens daily")
            row("On these days", rule.days.summary)
            row("Then block until", "Tomorrow")
            row("Unblocks allowed", rule.hardMode ? "No" : "Yes")
        }
    }

    private var appCountLabel: String {
        guard let list = rule.appList else { return "No apps" }
        return "\(list.name) · \(list.appCountLabel)"
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detailRow-\(label)")
    }
}
