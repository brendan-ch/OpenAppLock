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
                    TextField(CopyKey.appListsEditorNameFieldPlaceholder.resource, text: $name)
                        .submitLabel(.done)
                        .accessibilityIdentifier("appListNameField")
                } header: {
                    Text(.appListsEditorNameSectionHeader).textCase(nil)
                }

                // "Edit Apps" stays a list action (not a nav-bar item) but sits
                // in its own section above the apps it edits, so the picker entry
                // point reads before the current selection rather than after it.
                Section {
                    Button {
                        pickingApps = true
                    } label: {
                        Label(CopyKey.appListsEditAppsLabel.resource, systemImage: "checklist")
                    }
                    .accessibilityIdentifier("editAppsButton")
                }

                Section {
                    if AppSelectionCodec.count(of: selection) == 0 {
                        Text(.appListsEditorNoAppsYetMessage)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("emptySelectionLabel")
                    } else {
                        AppSelectionRows(selection: selection)
                    }
                } header: {
                    HStack {
                        Text(.appListsAppsSectionHeader).textCase(nil)
                        Spacer()
                        Text(countLabel).textCase(nil)
                    }
                }
            }
            .navigationTitle(list == nil ? CopyKey.appListsNewListLabel.resource : CopyKey.appListsEditListLabel.resource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CopyKey.appListsCloseButtonLabel.resource, systemImage: "xmark") {
                        attemptClose()
                    }
                    .accessibilityIdentifier("closeAppListButton")
                    .confirmationDialog(
                        CopyKey.appListsDiscardChangesConfirmationTitle.resource,
                        isPresented: $confirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button(CopyKey.appListsDiscardChangesAction.resource, role: .destructive) {
                            dismiss()
                        }
                        Button(CopyKey.appListsKeepEditingAction.resource, role: .cancel) {}
                    } message: {
                        Text(.appListsUnsavedEditsMessage)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(CopyKey.appListsSaveListAccessibilityLabel.resource)
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
        return count == 1 ? CopyKey.appListsOneAppCountLabel.string : CopyKey.appListsAppsCountFormat.string(count)
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
        let resolvedName = trimmed.isEmpty ? CopyKey.appListsUntitledListDefaultName.string : trimmed
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
            .navigationTitle(CopyKey.appListsEditAppsLabel.resource)
            .navigationBarTitleDisplayMode(.inline)
    }
}
