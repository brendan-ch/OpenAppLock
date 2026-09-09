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
    
    @State private var presentFailedValidation: Bool = false
    @State private var failedValidationReason: String? = nil

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
                        let validationResult = draft.validate()
                        if case .failure(let reason) = validationResult {
                            presentFailedValidation = true
                            failedValidationReason = reason.message
                        } else {
                            onCommit(draft.sanitized())
                        }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(CopyKey.ruleEditorAddRuleLabel.resource)
                    .accessibilityIdentifier("commitRuleButton")
                }
            }
            .alert(CopyKey.ruleDraftValidationFailedTitle.string, isPresented: $presentFailedValidation) {
                
            } message: {
                if let failedValidationReason = failedValidationReason {
                    Text(failedValidationReason)
                }
            }
    }
}
