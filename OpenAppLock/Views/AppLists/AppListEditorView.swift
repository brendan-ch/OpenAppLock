//
//  AppListEditorView.swift
//  OpenAppLock
//

import FamilyControls
import SwiftData
import SwiftUI

/// Creates or edits an app list, presented as a sheet overlay from the app-list
/// library. Its own NavigationStack carries a Close button — which, when there
/// are outstanding edits, confirms before discarding them (the standard iOS
/// pattern) — and a checkmark that persists the list. "Edit Apps" pushes Apple's
/// Screen Time picker, whose selections apply live; there is no separate Save
/// inside the picker, so the only commit point is this editor's checkmark.
///
/// Editing an existing list also gets an options menu (ellipsis) mirroring the
/// rule editor's, whose only item is a destructive Delete. Deleting confirms
/// first; a list still used by any rule can't be deleted and shows the same
/// "This list is in use" alert as the library's swipe action. The deletion
/// itself is delegated to the library via `onDelete`, so list removal and the
/// picker-selection cleanup stay in one place (see `AppListLibraryView`).
struct AppListEditorView: View {
    /// Nil creates a new list; otherwise edits (and saves into) the given one.
    let list: AppList?
    /// Performs the actual deletion (and any selection cleanup) for the Delete
    /// menu item. Nil for the New List flow, which has nothing to delete.
    var onDelete: (() -> Void)?
    var onComplete: (AppList) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selection: FamilyActivitySelection
    @State private var pickingApps = false
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false
    @State private var deletionBlocked = false

    /// What the editor opened with, for detecting outstanding edits on close.
    private let originalName: String
    private let originalSelection: FamilyActivitySelection

    init(
        list: AppList?,
        onDelete: (() -> Void)? = nil,
        onComplete: @escaping (AppList) -> Void
    ) {
        self.list = list
        self.onDelete = onDelete
        self.onComplete = onComplete
        let initialName = list?.name ?? ""
        let initialSelection = AppSelectionCodec.decode(list?.selectionData)
        self._name = State(initialValue: initialName)
        self._selection = State(initialValue: initialSelection)
        self.originalName = initialName
        self.originalSelection = initialSelection
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("List Name", text: $name)
                        .submitLabel(.done)
                        .accessibilityIdentifier("appListNameField")
                } header: {
                    Text("Name").textCase(nil)
                }

                // "Edit Apps" stays a list action (not a nav-bar item) but sits
                // in its own section above the apps it edits, so the picker entry
                // point reads before the current selection rather than after it.
                Section {
                    Button {
                        pickingApps = true
                    } label: {
                        Label("Edit Apps", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("editAppsButton")
                }

                Section {
                    if AppSelectionCodec.count(of: selection) == 0 {
                        Text("No apps yet. Edit Apps to choose what this list includes.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("emptySelectionLabel")
                    } else {
                        AppSelectionRows(selection: selection)
                    }
                } header: {
                    HStack {
                        Text("Apps").textCase(nil)
                        Spacer()
                        Text(countLabel).textCase(nil)
                    }
                }
            }
            .navigationTitle(list == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        attemptClose()
                    }
                    .accessibilityIdentifier("closeAppListButton")
                    .confirmationDialog(
                        "Discard Changes?",
                        isPresented: $confirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button("Discard Changes", role: .destructive) {
                            dismiss()
                        }
                        Button("Keep Editing", role: .cancel) {}
                    } message: {
                        Text("Your edits to this list haven't been saved.")
                    }
                }
                // Editing an existing list gets the rule-editor-style options
                // menu; its only action is a confirmed Delete.
                if list != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete", role: .destructive) {
                                attemptDelete()
                            }
                            .accessibilityIdentifier("deleteAppListButton")
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("List Actions")
                        .accessibilityIdentifier("appListActionsMenu")
                        .confirmationDialog(
                            "Delete this list?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                onDelete?()
                                dismiss()
                            }
                        } message: {
                            Text("This app list will be permanently removed.")
                        }
                        .alert("This list is in use", isPresented: $deletionBlocked) {
                            Button("OK", role: .cancel) {}
                        } message: {
                            Text("Remove it from the rules that use it before deleting.")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save List")
                    .accessibilityIdentifier("saveAppListButton")
                }
            }
            .navigationDestination(isPresented: $pickingApps) {
                AppPickerScreen(selection: $selection)
            }
        }
        // Block the swipe-to-dismiss while there are unsaved edits so the only
        // way out is the Close button, which routes through the discard prompt.
        .interactiveDismissDisabled(hasOutstandingEdits)
    }

    private var countLabel: String {
        let count = AppSelectionCodec.count(of: selection)
        return count == 1 ? "1 App" : "\(count) Apps"
    }

    private var hasOutstandingEdits: Bool {
        AppListEditState.hasOutstandingEdits(
            originalName: originalName,
            currentName: name,
            originalSelection: originalSelection,
            currentSelection: selection
        )
    }

    /// Close immediately when nothing changed; otherwise confirm the discard.
    private func attemptClose() {
        if hasOutstandingEdits {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    /// A list still used by a rule can't be deleted (the same guard the
    /// library's swipe action enforces), so surface the blocking alert instead
    /// of confirming. An unused list raises the delete confirmation.
    private func attemptDelete() {
        guard let list else { return }
        if AppList.isInUse(list, context: modelContext) {
            deletionBlocked = true
        } else {
            confirmingDelete = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let resolvedName = trimmed.isEmpty ? "Untitled List" : trimmed
        let data = AppSelectionCodec.encode(selection)
        let count = AppSelectionCodec.count(of: selection)

        if let list {
            list.name = resolvedName
            list.selectionData = data
            list.selectionCount = count
            Diag.log(.appList, .event, "saved list \"\(resolvedName)\" (edit) selCount=\(count)")
            onComplete(list)
        } else {
            let created = AppList(name: resolvedName, selectionData: data, selectionCount: count)
            modelContext.insert(created)
            Diag.log(.appList, .event, "saved list \"\(resolvedName)\" (new) selCount=\(count)")
            onComplete(created)
        }
        dismiss()
    }
}

/// Apple's Screen Time picker, pushed by "Edit Apps". It binds straight to the
/// editor's working selection, so selecting or deselecting an app applies the
/// change immediately — those edits are committed only when the editor is saved.
private struct AppPickerScreen: View {
    @Binding var selection: FamilyActivitySelection

    var body: some View {
        FamilyActivityPicker(selection: $selection)
            .navigationTitle("Edit Apps")
            .navigationBarTitleDisplayMode(.inline)
    }
}
