//
//  AppListDetailView.swift
//  OpenAppLock
//

import FamilyControls
import SwiftUI

/// Read-only view of an app list's contents. Shown while a Hard Mode rule is
/// actively blocking: the list itself stays locked (no name field, no "Edit
/// Apps", no Save), but the user can still see which apps the list includes —
/// viewing is never a back door out of the block.
struct AppListDetailView: View {
    let list: AppList

    private var selection: FamilyActivitySelection {
        AppSelectionCodec.decode(list.selectionData)
    }

    var body: some View {
        List {
            Section {
                if AppSelectionCodec.count(of: selection) == 0 {
                    Text("This list has no apps.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("appListDetailEmptyLabel")
                } else {
                    AppSelectionRows(selection: selection)
                }
            } header: {
                HStack {
                    Text("Apps").textCase(nil)
                    Spacer()
                    Text(list.appCountLabel).textCase(nil)
                }
            } footer: {
                Label(
                    "Hard Mode is on — this list is read-only until the block ends.",
                    systemImage: "lock.fill"
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("appListReadOnlyNotice")
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
