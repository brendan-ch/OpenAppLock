//
//  AppListLibraryView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The reusable app-list library: the saved lists, an Edit affordance, the New
/// List flow, swipe-to-delete, and the Hard Mode lock. It is always **pushed**
/// onto a navigation stack — by the rule editor's App List row (picker mode) or
/// by Settings ▸ Manage App Lists (management mode) — and opens the list editor
/// (`AppListEditorView`) as a **sheet overlay** for both Edit and New. Two modes:
///
/// - **Picker** (`selection` non-nil): each row shows a checkmark and tapping it
///   selects the list and calls `onPick`, which pops back to the rule editor.
///   Creating a list selects it without popping (its editor sheet just closes).
/// - **Management** (`selection` nil): no checkmark; tapping a row (when unlocked)
///   opens it for editing. Used by Settings ▸ Manage App Lists.
///
/// In both modes editing and deletion are disabled while any Hard Mode rule is
/// actively blocking — changing a list would be a back door out of the block.
struct AppListLibraryView: View {
    /// Picker mode when non-nil; management mode when nil.
    var selection: Binding<AppList?>?
    /// Called after a row is tapped in picker mode — the rule editor uses this
    /// to pop the pushed selection screen back to itself.
    var onPick: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: \AppList.createdAt) private var lists: [AppList]
    @Query private var rules: [BlockingRule]

    @State private var editingList: AppList?
    @State private var creatingList = false
    @State private var deletionBlocked = false

    private var isPicking: Bool { selection != nil }

    /// While any hard-mode rule is actively blocking, lists are read-only.
    private var listsLocked: Bool {
        !RulePolicy.canEditAppLists(rules: rules, usageFor: { enforcer.usage(for: $0) })
    }

    var body: some View {
        Group {
            if lists.isEmpty {
                ContentUnavailableView {
                    Label("No App Lists", systemImage: "square.stack.3d.up")
                } description: {
                    // Identifier on the description so it stays a distinct
                    // element instead of collapsing onto the action button.
                    Text("Create one to choose which apps a rule affects.")
                        .accessibilityIdentifier("emptyAppListsLabel")
                } actions: {
                    Button("New List") {
                        creatingList = true
                    }
                    .accessibilityIdentifier("newAppListButton")
                }
            } else {
                List {
                    Section {
                        ForEach(lists) { list in
                            listRow(list)
                        }
                    } header: {
                        Text("Your App Lists").textCase(nil)
                    } footer: {
                        if listsLocked {
                            Label(
                                "Hard Mode is on — app lists are locked until the block ends.",
                                systemImage: "lock.fill"
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("appListsLockedNotice")
                        }
                    }
                    Section {
                        Button {
                            creatingList = true
                        } label: {
                            Label("New List", systemImage: "plus")
                        }
                        .accessibilityIdentifier("newAppListButton")
                    }
                }
            }
        }
        // The editor pops out as its own sheet overlay (with Close + confirm and
        // a discard prompt); it dismisses itself, which clears these bindings.
        .sheet(isPresented: $creatingList) {
            AppListEditorView(list: nil) { created in
                selection?.wrappedValue = created
            }
        }
        .sheet(item: $editingList) { list in
            AppListEditorView(list: list) { _ in }
        }
        .alert("This list is in use", isPresented: $deletionBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Remove it from the rules that use it before deleting.")
        }
    }

    @ViewBuilder
    private func listRow(_ list: AppList) -> some View {
        if isPicking {
            // Picker mode: tapping the row selects the list, so it keeps a
            // distinct trailing Edit affordance to open the list for editing.
            HStack {
                Button {
                    selection?.wrappedValue = list
                    onPick?()
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
                if !listsLocked {
                    Button("Edit") {
                        editingList = list
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("editAppListButton-\(list.name)")
                }
            }
            .buttonStyle(.borderless)
            .swipeActions { deleteAction(list) }
        } else {
            // Management mode: the whole row taps to edit (a full-width target),
            // with a disclosure chevron instead of a redundant Edit button.
            Button {
                if !listsLocked { editingList = list }
            } label: {
                HStack {
                    rowText(list)
                    Spacer()
                    if !listsLocked {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
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
            Text(list.appCountLabel)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private func deleteAction(_ list: AppList) -> some View {
        if !listsLocked {
            Button("Delete", role: .destructive) {
                delete(list)
            }
        }
    }

    private func isSelected(_ list: AppList) -> Bool {
        selection?.wrappedValue?.id == list.id
    }

    private func delete(_ list: AppList) {
        guard !AppList.isInUse(list, context: modelContext) else {
            deletionBlocked = true
            return
        }
        if isSelected(list) {
            selection?.wrappedValue = nil
        }
        modelContext.delete(list)
    }
}
