//
//  AppListLibraryView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The reusable app-list library: the saved lists, per-row Edit/View
/// affordances, the New List flow, swipe-to-delete, and the Lock While Blocking lock. It
/// is always **pushed** onto a navigation stack — by the rule editor's App List
/// row (picker mode) or by Settings ▸ Manage App Lists (management mode). Two
/// modes:
///
/// - **Picker** (`selection` non-nil): each row's tap **toggles** its membership
///   in the rule's selection, so multiple lists can be combined into one rule.
///   A trailing button opens the list — "Edit" (the full editor as a **sheet
///   overlay**) when unlocked, "View" (the read-only `AppListDetailView`) while
///   a Lock While Blocking rule blocks. Creating a list appends it to the
///   selection; leaving the picker is the navigation back button.
/// - **Management** (`selection` nil): no checkmark; tapping the row opens it —
///   the editor sheet when unlocked, the read-only `AppListDetailView` while
///   locked. Used by Settings ▸ Manage App Lists.
///
/// Editing and deletion are disabled in both modes while any Lock While Blocking rule is
/// actively blocking — changing a list would be a back door out of the block —
/// but viewing a list's apps stays allowed, since reading can't weaken a block.
struct AppListLibraryView: View {
    /// Picker mode when non-nil; management mode when nil. Multiple selected
    /// lists combine into one rule selection.
    var selection: Binding<[AppList]>?
    /// Called after the picker appends a newly created list — kept so hosts can
    /// react without popping the pushed screen.
    var onPick: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    // Alphabetical by name (see `AppList.displayOrder`).
    @Query(sort: AppList.displayOrder) private var lists: [AppList]
    @Query private var rules: [BlockingRule]

    @State private var editingList: AppList?
    @State private var viewingList: AppList?
    @State private var creatingList = false
    @State private var deletionBlocked = false
    @State private var pendingDeletionList: AppList?
    /// Set by the editor's Delete menu item; the removal runs after the editor
    /// sheet dismisses (see the `.sheet(item:onDismiss:)` below).
    @State private var editorDeletionList: AppList?

    private var isPicking: Bool { selection != nil }

    /// While any hard-mode rule is actively blocking, lists are read-only.
    private var listsLocked: Bool {
        !RulePolicy.canEditAppLists(snapshots: rules.map(\.dto), usageFor: { enforcer.usage(for: $0) })
    }

    var body: some View {
        Group {
            if lists.isEmpty {
                ContentUnavailableView {
                    Label(CopyKey.appListsLibraryEmptyStateTitle.resource, systemImage: "square.stack.3d.up")
                } description: {
                    // Identifier on the description so it stays a distinct
                    // element instead of collapsing onto the action button.
                    Text(.appListsLibraryEmptyStateDescription)
                        .accessibilityIdentifier("emptyAppListsLabel")
                } actions: {
                    Button(CopyKey.appListsNewListLabel.resource) {
                        creatingList = true
                    }
                    .accessibilityIdentifier("emptyStateNewAppListButton")
                }
            } else {
                List {
                    Section {
                        ForEach(lists) { list in
                            listRow(list)
                        }
                    } header: {
                        Text(.appListsLibraryYourAppListsSectionHeader).textCase(nil)
                    } footer: {
                        if listsLocked {
                            Label(
                                CopyKey.appListsLibraryLockedFooter.resource,
                                systemImage: "lock.fill"
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("appListsLockedNotice")
                        }
                    }
                }
            }
        }
        // Creating a new list stays allowed even while lists are locked — a new,
        // unused list cannot weaken an active block — so the "+" is never gated.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(CopyKey.appListsNewListLabel.resource, systemImage: "plus") {
                    creatingList = true
                }
                .accessibilityIdentifier("newAppListButton")
            }
        }
        // The editor pops out as its own sheet overlay (with Close + confirm and
        // a discard prompt); it dismisses itself, which clears these bindings.
        .sheet(isPresented: $creatingList) {
            AppListEditorView(list: nil) { created in
                if var current = selection?.wrappedValue, !current.contains(where: { $0.id == created.id }) {
                    current.append(created)
                    selection?.wrappedValue = current
                }
                onPick?()
            }
        }
        // The editor's Delete menu item marks the list and dismisses; the removal
        // runs in `onDismiss`, once the sheet is gone, so the editor never renders
        // a deleted model (mirrors the rule detail's deferred delete). Both delete
        // paths still funnel through `performDelete`.
        .sheet(item: $editingList, onDismiss: {
            if let list = editorDeletionList {
                performDelete(list)
                editorDeletionList = nil
            }
        }) { list in
            AppListEditorView(list: list, onDelete: { editorDeletionList = list }) { _ in }
        }
        .navigationDestination(item: $viewingList) { list in
            AppListDetailView(list: list)
        }
        .alert(Text(.appListsLibraryDeletionBlockedAlertTitle), isPresented: $deletionBlocked) {
        } message: {
            Text(.appListsLibraryDeletionBlockedAlertMessage)
        }
        // Swipe-to-delete confirms before removing the list (in-use lists hit the
        // alert above and never reach this).
        .confirmationDialog(
            CopyKey.appListsDeleteConfirmationTitle.string,
            isPresented: Binding(
                get: { pendingDeletionList != nil },
                set: { if !$0 { pendingDeletionList = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletionList
        ) { list in
            Button(CopyKey.appListsLibraryDeleteButtonLabel.resource, role: .destructive) {
                performDelete(list)
                pendingDeletionList = nil
            }
        } message: { _ in
            Text(.appListsDeleteConfirmationMessage)
        }
    }

    @ViewBuilder
    private func listRow(_ list: AppList) -> some View {
        if isPicking {
            // Picker mode: tapping the row toggles the list in the rule's
            // selection, so it keeps a distinct trailing Edit affordance to
            // open the list for editing.
            HStack {
                Button {
                    toggle(list)
                } label: {
                    HStack {
                        Image(systemName: isSelected(list) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                isSelected(list) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary)
                            )
                            .frame(width: 28)
                        rowText(list)
                    }
                }
                .accessibilityIdentifier("appListRow-\(list.name)")
                Spacer()
                // Locked lists stay read-only (no "Edit"), but can still be
                // opened to view their apps; unlocked lists open the editor.
                if listsLocked {
                    Button(CopyKey.appListsLibraryViewButtonLabel.resource) {
                        viewingList = list
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("viewAppListButton-\(list.name)")
                } else {
                    Button(CopyKey.appListsLibraryEditButtonLabel.resource) {
                        editingList = list
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("editAppListButton-\(list.name)")
                }
            }
            .buttonStyle(.borderless)
            .swipeActions { deleteAction(list) }
        } else {
            // Management mode: the whole row taps in (a full-width target).
            // Unlocked, it opens the editor; locked, it opens the read-only
            // detail so the apps stay viewable.
            Button {
                if listsLocked { viewingList = list } else { editingList = list }
            } label: {
                HStack {
                    rowText(list)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("appListRow-\(list.name)")
            .swipeActions { deleteAction(list) }
        }
    }

    private func rowText(_ list: AppList) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(list.name)
                .foregroundStyle(Color.primary)
            Text(list.appAndRuleCountLabel)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private func deleteAction(_ list: AppList) -> some View {
        if !listsLocked {
            Button(CopyKey.appListsLibraryDeleteButtonLabel.resource, role: .destructive) {
                attemptDelete(list)
            }
        }
    }

    private func isSelected(_ list: AppList) -> Bool {
        selection?.wrappedValue.contains { $0.id == list.id } ?? false
    }

    /// Adds or removes the list from the picker's selection binding
    /// (tapping another list never replaces prior selections).
    private func toggle(_ list: AppList) {
        guard var current = selection?.wrappedValue else { return }
        if let index = current.firstIndex(where: { $0.id == list.id }) {
            current.remove(at: index)
        } else {
            current.append(list)
        }
        selection?.wrappedValue = current
    }

    /// A list still used by a rule can't be deleted — show the blocking alert.
    /// An unused list raises the delete confirmation; `performDelete` removes it.
    private func attemptDelete(_ list: AppList) {
        guard !AppList.isInUse(list, context: modelContext) else {
            deletionBlocked = true
            return
        }
        pendingDeletionList = list
    }

    private func performDelete(_ list: AppList) {
        if let current = selection?.wrappedValue {
            selection?.wrappedValue = current.filter { $0.id != list.id }
        }
        modelContext.delete(list)
    }
}

#if DEBUG
/// Seeds several app lists, inserted **out of** alphabetical order, so the
/// preview demonstrates the library sorting alphabetically by name regardless
/// of creation order (see `AppList.displayOrder`). Mixed case shows the
/// case-insensitive ordering ("games" sorts with the G's, not after "Social").
@MainActor
private func appListLibraryOrderingPreview() -> some View {
    let container = try! ModelContainer(
        for: BlockingRule.self, AppList.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    for name in ["Social", "Distractions", "Productivity", "games"] {
        container.mainContext.insert(AppList(name: name, selectionCount: 3))
    }
    return NavigationStack {
        AppListLibraryView()
    }
    .modelContainer(container)
    .environment(RuleEnforcer(shields: MockShieldController()))
}

#Preview("Alphabetical order") {
    appListLibraryOrderingPreview()
}
#endif
