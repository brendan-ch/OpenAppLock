//
//  NewRuleSheet.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// "New Rule" as a plain list: a Rule Type section, then the preset sections.
/// Picking either pushes the editor; committing saves and closes the sheet.
struct NewRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var pendingDraft: RuleDraft?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RuleKind.allCases, id: \.self) { kind in
                        kindRow(kind)
                    }
                } header: {
                    Text(.newRuleRuleTypeSectionHeader).textCase(nil)
                }
                ForEach(RulePresetSection.all) { section in
                    Section {
                        ForEach(section.presets) { preset in
                            presetRow(preset)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                            Text(section.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .textCase(nil)
                    }
                }
            }
            .navigationTitle(CopyKey.newRuleNavigationTitle.resource)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CopyKey.newRuleCloseButton.resource, systemImage: "xmark") {
                        dismiss()
                    }
                    .accessibilityIdentifier("closeNewRuleButton")
                }
            }
            .navigationDestination(item: $pendingDraft) { draft in
                RuleEditorView(
                    draft: draft,
                    onCommit: { committed in
                        committed.insertRule(into: modelContext)
                        dismiss()
                    }
                )
            }
        }
    }

    private func kindRow(_ kind: RuleKind) -> some View {
        Button {
            pendingDraft = RuleDraft(kind: kind)
        } label: {
            HStack {
                Image(systemName: kind.symbolName)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .foregroundStyle(Color.primary)
                    Text(kind.exampleText)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityIdentifier("ruleKind-\(kind.rawValue)")
    }

    private func presetRow(_ preset: RulePreset) -> some View {
        Button {
            pendingDraft = RuleDraft(preset: preset)
        } label: {
            HStack {
                Image(systemName: preset.symbolName)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .foregroundStyle(Color.primary)
                    Text(CopyKey.newRulePresetSummaryFormat.string(preset.schedule.timeRangeLabel, preset.days.summary))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                // A chevron (matching the Rule Type rows) is the honest
                // affordance: picking a preset pushes the editor to confirm,
                // it does not add the rule outright.
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityIdentifier("preset-\(preset.id)")
    }
}
