//
//  RuleDetailSheet.swift
//  OpenAppLock
//

import DeviceActivity
import FamilyControls
import SwiftData
import SwiftUI

/// Rule summary presented as a plain sheet that doubles as the rule editor: the
/// rule's facts as labeled rows, an options menu (ellipsis), and an "Edit" button
/// that **cross-fades the sheet in place** into `RuleEditorForm` rather than
/// pushing a new screen. Editing keeps the same surface — Edit fades the detail
/// out and the form in (fade-through, no overlap); Save commits and fades back;
/// Close fades back too, confirming first when there are unsaved edits (the
/// discard prompt). While editing with unsaved edits the sheet's swipe-to-dismiss
/// is blocked, so the only way out is the Close button.
///
/// The options menu offers a temporary Pause (a confirmed 15-minute lift) or
/// Resume on a pausable/paused block, plus Disable/Enable and a confirmed Delete.
/// A hard-locked rule hides both the menu and Edit and shows a lock notice instead.
struct RuleDetailSheet: View {
    let rule: BlockingRule

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]

    @State private var isEditing = false
    /// Working copy edited in place; re-captured from the rule on every mode
    /// switch, so each edit starts fresh and discarding simply drops it.
    @State private var draft: RuleDraft
    /// What the current edit opened with, for the discard prompt's dirty check.
    @State private var originalDraft: RuleDraft
    /// Drives the fade-through: faded to 0, the mode swaps, then back to 1.
    @State private var contentOpacity: Double = 1
    @State private var pendingDeletion = false
    @State private var pendingPause = false
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false

    init(rule: BlockingRule) {
        self.rule = rule
        let draft = RuleDraft(rule: rule)
        _draft = State(initialValue: draft)
        _originalDraft = State(initialValue: draft)
    }

    private var hasOutstandingEdits: Bool {
        RuleEditState.hasOutstandingEdits(original: originalDraft, current: draft)
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                modeContent(now: timeline.date)
            }
        }
        // While editing with unsaved changes, block the sheet's swipe-to-dismiss
        // so the only way out is Close, which routes through the discard prompt
        // (mirrors AppListEditorView).
        .interactiveDismissDisabled(isEditing && hasOutstandingEdits)
        .onDisappear {
            if pendingDeletion {
                modelContext.delete(rule)
            }
        }
    }

    /// The cross-faded body: the read-only detail or the editor form, with the
    /// navigation bar morphing between them. Only the content fades (via
    /// `contentOpacity`); the toolbar swaps during the invisible moment.
    private func modeContent(now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now)
        return Group {
            if isEditing {
                RuleEditorForm(draft: $draft)
            } else {
                detailList(dto: dto, usage: usage, now: now)
            }
        }
        .opacity(contentOpacity)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(dto: dto, usage: usage, now: now) }
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

    private func detailList(dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date) -> some View {
        List {
            Section("General") {
                generalRows(dto: dto, usage: usage, now: now)
            }

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
    }

    /// The navigation bar, shared across both modes so it morphs rather than
    /// pops: a constant Close button (and options menu), a trailing primary that
    /// flips Edit ⇄ Save, and a principal title that stays the rule's name.
    @ToolbarContentBuilder
    private func toolbar(dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
                attemptClose()
            }
            .accessibilityIdentifier("closeDetailButton")
            // Discard prompt for closing the editor with unsaved edits; attached
            // to the Close button so it anchors there (mirrors AppListEditorView).
            .confirmationDialog(
                "Discard Changes?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    setEditing(false)
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your edits to this rule haven't been saved.")
            }
        }

        // The options menu and the Edit/Save button sit behind the live
        // `canEdit` gate, re-checked every render. If a hard block engages while
        // the form is open, Save (and the weakening menu actions) disappear, so
        // in-progress edits can only be discarded via Close — never committed.
        // That is the Hard Mode invariant (an active hard block can't be
        // weakened), not an oversight: it closes the commit window the old
        // pushed editor left open.
        if RulePolicy.canEdit(dto, usage: usage, at: now) {
            ToolbarItem(placement: .topBarTrailing) {
                ruleActionsMenu(dto: dto, usage: usage, now: now)
            }
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button(role: .confirm) {
                        commitEdit()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("doneButton")
                } else {
                    Button("Edit", systemImage: "pencil") {
                        setEditing(true)
                    }
                    .accessibilityIdentifier("editRuleButton")
                }
            }
        }

        ToolbarItem(placement: .principal) {
            if isEditing {
                Text(draft.sanitized().name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("ruleEditorTitle")
            } else {
                Text(rule.name)
                    .font(.headline)
                    .accessibilityIdentifier("detailRuleName")
            }
        }
    }

    /// The options menu, present in both modes so the bar doesn't pop. Pause /
    /// Resume and Disable / Enable act on the live rule, so they appear only in
    /// view mode — invoking them mid-edit would silently drop the draft; a
    /// confirmed Delete is offered in both. Surfaced only when the rule is not
    /// hard-locked, so a hard block exposes no weakening action.
    @ViewBuilder
    private func ruleActionsMenu(
        dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date
    ) -> some View {
        Menu {
            if !isEditing {
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
            }
            Button("Delete", role: .destructive) {
                confirmingDelete = true
            }
            .accessibilityIdentifier("deleteRuleButton")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Rule Actions")
        .accessibilityIdentifier("ruleActionsMenu")
        // Delete confirmation; attached to the menu so it anchors under the
        // ellipsis. The menu dismisses first, then the dialog presents.
        .confirmationDialog(
            "Delete this rule?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                pendingDeletion = true
                dismiss()
            }
        } message: {
            Text("This rule will be permanently removed.")
        }
    }

    // MARK: - Mode transitions

    /// Cross-fades to the given mode: fade the content out, swap modes while it is
    /// invisible (re-capturing a fresh draft so each edit starts clean and a
    /// discard simply drops the working copy), then fade back in.
    private func setEditing(_ editing: Bool) {
        // Ignore re-entrant calls while a fade is in flight. A transition only
        // ever starts from a settled state (opacity 1); without this guard a
        // second call mid-fade would re-animate `contentOpacity` toward a value
        // it is already heading to, and a no-op animation's completion may never
        // fire — which would strand the content invisible at opacity 0.
        guard contentOpacity == 1 else { return }
        withAnimation(.easeIn(duration: 0.18)) {
            contentOpacity = 0
        } completion: {
            isEditing = editing
            let fresh = RuleDraft(rule: rule)
            draft = fresh
            originalDraft = fresh
            withAnimation(.easeOut(duration: 0.18)) {
                contentOpacity = 1
            }
        }
    }

    /// Close means dismiss the sheet in view mode, and leave edit mode in edit
    /// mode — confirming first when there are unsaved edits.
    private func attemptClose() {
        guard isEditing else {
            dismiss()
            return
        }
        if hasOutstandingEdits {
            confirmingDiscard = true
        } else {
            setEditing(false)
        }
    }

    /// Applies the (sanitized) edits to the rule and fades back to the detail.
    private func commitEdit() {
        draft.sanitized().apply(to: rule)
        setEditing(false)
    }

    // MARK: - Detail rows

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
    private func generalRows(dto: RuleSnapshotDTO, usage: RuleUsageDTO?, now: Date) -> some View {
        let status = dto.status(at: now, usage: usage)
        row("Kind", dto.kind.displayName)
        row("Status", dto.rowContext(for: status, usage: usage ?? RuleUsageDTO(), relativeTo: now))
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
