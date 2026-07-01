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
                    Text(.appListsDetailEmptyMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("appListDetailEmptyLabel")
                } else {
                    AppSelectionRows(selection: selection)
                }
            } header: {
                HStack {
                    Text(.appListsAppsSectionHeader).textCase(nil)
                    Spacer()
                    Text(list.appCountLabel).textCase(nil)
                }
            } footer: {
                Label(
                    CopyKey.appListsDetailReadOnlyFooter.resource,
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
