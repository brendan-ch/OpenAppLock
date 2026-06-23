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
struct AppListEditorView: View {
    /// Nil creates a new list; otherwise edits (and saves into) the given one.
    let list: AppList?
    var onComplete: (AppList) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selection: FamilyActivitySelection
    @State private var pickingApps = false
    @State private var confirmingDiscard = false

    /// What the editor opened with, for detecting outstanding edits on close.
    private let originalName: String
    private let originalSelection: FamilyActivitySelection

    init(list: AppList?, onComplete: @escaping (AppList) -> Void) {
        self.list = list
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

                Section {
                    if AppSelectionCodec.count(of: selection) == 0 {
                        Text("No apps yet. Edit Apps to choose what this list includes.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("emptySelectionLabel")
                    } else {
                        AppSelectionRows(selection: selection)
                    }
                    Button {
                        pickingApps = true
                    } label: {
                        Label("Edit Apps", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("editAppsButton")
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
