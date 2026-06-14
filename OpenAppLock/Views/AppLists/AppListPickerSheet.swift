//
//  AppListPickerSheet.swift
//  OpenAppLock
//

import SwiftUI

/// Chooses the app list a rule uses. Wraps the shared `AppListLibraryView` in
/// picker mode (checkmark + select-and-dismiss); the library handles the list
/// rows, Edit/New flows, deletion, and the Hard Mode lock.
struct AppListPickerSheet: View {
    @Binding var selected: AppList?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppListLibraryView(selection: $selected, onPick: { dismiss() })
                .navigationTitle("App List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            dismiss()
                        }
                        .accessibilityIdentifier("closeAppListPickerButton")
                    }
                }
        }
    }
}

extension AppList {
    /// "4 Apps" / "1 App" label shared by the picker, editor, and detail rows.
    var appCountLabel: String {
        selectionCount == 1 ? "1 App" : "\(selectionCount) Apps"
    }
}
