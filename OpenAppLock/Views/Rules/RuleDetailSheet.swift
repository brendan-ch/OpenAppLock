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
            // report extension (the only place the data is available). Pushed to a
            // full page rather than embedded here: a `DeviceActivityReport` renders
            // out-of-process and never reports its content height back, so in a
            // List row it clips at whatever fixed frame it is given — a full page
            // lets it use the whole screen. Time-limit rules only (schedules have
            // no budget; open limits are governed by opens, not duration), and only
            // with a non-empty selection — an empty `DeviceActivityFilter` matches
            // *all* device activity. Gated under UI testing (the system view does
            // not run in the harness).
            if rule.kind == .timeLimit && hasUsageSelection
                && !LaunchConfiguration.current.isUITesting {
                Section {
                    NavigationLink {
                        RuleUsageReportPage(filter: usageFilter)
                    } label: {
                        Label("Today's Usage", systemImage: "chart.bar")
                    }
                    .accessibilityIdentifier("usageReportLink")
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

    /// Whether this rule selects any app/category/web domain to scope the report
    /// to. An empty selection makes `usageFilter`'s token sets empty, which
    /// `DeviceActivityFilter` treats as "no restriction" (all device activity), so
    /// the panel is hidden rather than enumerating every app.
    private var hasUsageSelection: Bool {
        let selection = AppSelectionCodec.decode(rule.appList?.selectionData)
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    /// Today's `.daily` filter scoped to this rule's selection, so the report
    /// extension attributes only this rule's apps/categories/web domains. The
    /// interval is the whole day (start-of-day to start-of-next-day), not
    /// `…end: .now` — a stable value so the filter doesn't change on every 30s
    /// `TimelineView` tick and reload/flash the pushed report while it's open. The
    /// daily segment still reports today's usage-so-far (no future activity to add).
    private var usageFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let interval = DateInterval(start: startOfDay, end: endOfDay)
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

/// A full-page host for a rule's usage `DeviceActivityReport`, pushed from the
/// detail sheet. The report renders out-of-process and never reports its content
/// height to the host, so a `List` row clips it; a full page gives it the whole
/// screen to render the total and per-app rows (it scrolls if there are many).
private struct RuleUsageReportPage: View {
    let filter: DeviceActivityFilter

    var body: some View {
        DeviceActivityReport(.ruleUsage, filter: filter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Usage")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("ruleUsageReport")
    }
}
