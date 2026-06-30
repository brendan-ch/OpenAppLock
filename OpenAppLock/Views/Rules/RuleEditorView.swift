//
//  RuleEditorView.swift
//  OpenAppLock
//

import SwiftUI

/// The New Rule editor: `RuleEditorForm` pushed inside the New Rule sheet's
/// NavigationStack, with an inline title and a checkmark that commits the draft.
/// Editing an existing rule no longer pushes this — the rule detail sheet embeds
/// `RuleEditorForm` directly and cross-fades into it in place (see
/// `RuleDetailSheet`), so this view now only ever creates.
struct RuleEditorView: View {
    @State var draft: RuleDraft
    var onCommit: (RuleDraft) -> Void

    var body: some View {
        RuleEditorForm(draft: $draft)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(draft.sanitized().name)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityIdentifier("ruleEditorTitle")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onCommit(draft.sanitized())
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Add Rule")
                    .accessibilityIdentifier("commitRuleButton")
                }
            }
    }
}
