//
//  RuleDetailSheet.swift
//  OpenAppLock
//

import DeviceActivity
import FamilyControls
import SwiftData
import SwiftUI

/// Rule summary presented as a plain sheet: an inline title with a live status
/// caption, the rule's facts as labeled rows, an "Edit" button, and an options
/// menu (ellipsis) mirroring the editor's. The menu offers a temporary Pause (a
/// confirmed 15-minute lift) or Resume on a pausable/paused block, plus Disable/
/// Enable and Delete. A hard-locked rule hides both the menu and Edit and shows
/// a lock notice instead.
struct RuleDetailSheet: View {
    let rule: BlockingRule

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]
    @State private var isEditing = false
    @State private var pendingDeletion = false
    @State private var pendingPause = false

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
                if !RulePolicy.canEdit(dto, usage: usage, at: now) {
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
            
            if RulePolicy.canEdit(dto, usage: usage, at: now) {
                ToolbarItem(placement: .topBarTrailing) {
                    ruleActionsMenu(dto: dto, usage: usage, now: now)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        isEditing = true
                    }
                    .accessibilityIdentifier("editRuleButton")
                }
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
        // Pause confirmation, triggered by the options menu's "Pause" item.
        // Attached here (outside the Menu) so the menu dismisses first and the
        // dialog then presents reliably.
        .confirmationDialog(
            "Pause \(rule.name)?",
            isPresented: $pendingPause,
            titleVisibility: .visible
        ) {
            Button("Pause for 15 minutes") {
                enforcer.pause(rule, rules: rules)
                pendingPause = false
            }
        } message: {
            Text("Apps unblock for 15 minutes, then blocking resumes automatically.")
        }
    }

    /// The viewing-view options menu, mirroring the editor's. A temporary Pause
    /// (when the block is pausable) or Resume (when paused) leads, then Disable/
    /// Enable and Delete. Surfaced only when the rule is not hard-locked, so a
    /// hard block exposes no weakening action — the lock notice shows instead.
    @ViewBuilder
    private func ruleActionsMenu(
        dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date
    ) -> some View {
        Menu {
            if dto.isPaused(at: now) {
                Button("Resume Blocking") {
                    enforcer.resume(rule, rules: rules)
                }
                .accessibilityIdentifier("resumeRuleButton")
            } else if RulePolicy.canPause(dto, usage: usage, at: now) {
                Button("Pause for 15 minutes") {
                    pendingPause = true
                }
                .accessibilityIdentifier("pauseRuleButton")
            }
            Button(rule.isEnabled ? "Disable" : "Enable") {
                rule.isEnabled.toggle()
                rule.pausedUntil = nil
            }
            .accessibilityIdentifier("disableRuleButton")
            Button("Delete", role: .destructive) {
                pendingDeletion = true
                dismiss()
            }
            .accessibilityIdentifier("deleteRuleButton")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Rule Actions")
        .accessibilityIdentifier("ruleActionsMenu")
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
            row("Pausing allowed", rule.hardMode ? "No" : "Yes")
        case .timeLimit(let config):
            row("When I use", appCountLabel)
            row("For this long", "\(config.dailyLimitMinutes)m daily")
            row("On these days", rule.days.summary)
            row("Then block until", "Tomorrow")
            row("Pausing allowed", rule.hardMode ? "No" : "Yes")
        case .openLimit(let config):
            row("When I open", appCountLabel)
            row("More than", "\(config.maxOpens) opens daily")
            row("On these days", rule.days.summary)
            row("Then block until", "Tomorrow")
            row("Pausing allowed", "No")
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

#if DEBUG
/// Renders the detail sheet for one scenario against an in-memory rule, so the
/// previews exercise realistic layouts (app list attached, days, hard mode)
/// without touching the on-disk store. The view keeps the container alive via
/// `.modelContainer`, which is also what supplies its `modelContext`.
@MainActor
private func ruleDetailPreview(
    name: String,
    configuration: RuleConfiguration,
    hardMode: Bool,
    days: Set<Weekday> = Weekday.weekdays,
    appList: (name: String, appCount: Int)? = ("Focus Apps", 4)
) -> some View {
    let container = try! ModelContainer(
        for: BlockingRule.self, AppList.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let rule = BlockingRule(
        name: name, configuration: configuration, hardMode: hardMode, days: days)
    // Relationship assignment is only safe once both models are inserted.
    container.mainContext.insert(rule)
    if let appList {
        let list = AppList(name: appList.name, selectionCount: appList.appCount)
        container.mainContext.insert(list)
        rule.appList = list
    }
    return RuleDetailSheet(rule: rule)
        .modelContainer(container)
        .environment(RuleEnforcer(shields: MockShieldController()))
}

#Preview("Schedule") {
    ruleDetailPreview(
        name: "Work Time",
        configuration: .schedule(
            ScheduleConfig(
                startMinutes: 9 * 60, endMinutes: 17 * 60,
                selectionMode: .block)),
        hardMode: false)
}

#Preview("Active · pausable") {
    // A full-day (start == end) non-Hard-Mode schedule reads as actively blocking
    // whenever the preview runs, so the Pause control is offered.
    ruleDetailPreview(
        name: "Work Time",
        configuration: .schedule(ScheduleConfig(startMinutes: 0, endMinutes: 0)),
        hardMode: false,
        days: Weekday.everyDay)
}

#Preview("Schedule · Hard Mode") {
    // A full-day window (start == end) on every day reads as actively blocking
    // whenever the preview runs, surfacing the Hard Mode lock notice and hiding
    // Edit — the state that is otherwise hard to catch in a static preview.
    ruleDetailPreview(
        name: "Locked In",
        configuration: .schedule(ScheduleConfig(startMinutes: 0, endMinutes: 0)),
        hardMode: true,
        days: Weekday.everyDay)
}

#Preview("Time Limit") {
    ruleDetailPreview(
        name: "Time Keeper",
        configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 45)),
        hardMode: false)
}

#Preview("Open Limit") {
    ruleDetailPreview(
        name: "Gate Keeper",
        configuration: .openLimit(OpenLimitConfig(maxOpens: 5)),
        hardMode: false,
        days: Weekday.everyDay)
}
#endif
