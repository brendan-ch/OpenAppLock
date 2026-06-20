//
//  AppSelectionRows.swift
//  OpenAppLock
//

import FamilyControls
import SwiftUI

/// Read-only rows for everything a `FamilyActivitySelection` contains.
/// FamilyControls' `Label` initializers resolve the opaque tokens to icon +
/// name. Shared by the app-list editor and the read-only detail so both render
/// a list's contents identically.
struct AppSelectionRows: View {
    let selection: FamilyActivitySelection

    var body: some View {
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
}
