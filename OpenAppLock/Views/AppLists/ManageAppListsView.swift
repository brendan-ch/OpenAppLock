//
//  ManageAppListsView.swift
//  OpenAppLock
//

import SwiftUI

/// Standalone app-list management (Settings ▸ Manage App Lists): the same
/// create / edit / delete flow the rule editor's picker uses, minus selection.
/// Pushed inside the Settings tab's navigation stack.
struct ManageAppListsView: View {
    var body: some View {
        AppListLibraryView()
            .navigationTitle(CopyKey.appListsManageNavigationTitle.resource)
            .navigationBarTitleDisplayMode(.inline)
    }
}
