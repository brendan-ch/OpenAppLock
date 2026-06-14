//
//  AppListEditorView.swift
//  OpenAppLock
//

import FamilyControls
import SwiftData
import SwiftUI

/// Creates or edits an app list. A plain List (consistent with the rest of
/// the app) holds the name field and the apps currently in the list; "Edit
/// Apps" pushes Apple's Screen Time picker, whose Save applies the new
/// selection back here. The navigation-bar checkmark persists the list.
struct AppListEditorView: View {
    /// Nil creates a new list; otherwise edits (and saves into) the given one.
    let list: AppList?
    var onComplete: (AppList) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var selection: FamilyActivitySelection
    @State private var pickingApps = false

    init(list: AppList?, onComplete: @escaping (AppList) -> Void) {
        self.list = list
        self.onComplete = onComplete
        self._name = State(initialValue: list?.name ?? "")
        self._selection = State(initialValue: AppSelectionCodec.decode(list?.selectionData))
    }

    var body: some View {
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
                    selectionRows
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

    /// Rows for everything the selection contains. FamilyControls' Label
    /// initializers resolve the opaque tokens to icon + name.
    @ViewBuilder
    private var selectionRows: some View {
        ForEach(Array(selection.applicationTokens), id: \.self) { token in
            Label(token)
        }
        ForEach(Array(selection.categoryTokens), id: \.self) { token in
            Label(token)
        }
        ForEach(Array(selection.webDomainTokens), id: \.self) { token in
            Label(token)
        }
    }

    private var countLabel: String {
        let count = AppSelectionCodec.count(of: selection)
        return count == 1 ? "1 App" : "\(count) Apps"
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
            onComplete(list)
        } else {
            let created = AppList(name: resolvedName, selectionData: data, selectionCount: count)
            modelContext.insert(created)
            onComplete(created)
        }
    }
}

/// Screen 2: Apple's Screen Time picker. Save applies the working selection
/// back to the editor and pops; the back swipe discards it.
private struct AppPickerScreen: View {
    @Binding var selection: FamilyActivitySelection

    @Environment(\.dismiss) private var dismiss
    @State private var working: FamilyActivitySelection

    init(selection: Binding<FamilyActivitySelection>) {
        self._selection = selection
        self._working = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        FamilyActivityPicker(selection: $working)
            .navigationTitle("Edit Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        saveSelection()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save Apps")
                    .accessibilityIdentifier("confirmSelectionButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text(selectionSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("selectionCountLabel")
                    Button {
                        saveSelection()
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("saveSelectionButton")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
    }

    private var selectionSummary: String {
        let count = AppSelectionCodec.count(of: working)
        return count == 1 ? "1 App Selected" : "\(count) Apps Selected"
    }

    private func saveSelection() {
        selection = working
        dismiss()
    }
}
