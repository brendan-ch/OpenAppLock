//
//  RuleEditorForm.swift
//  OpenAppLock
//

import SwiftUI

/// The rule editor's form body — the name field plus the per-kind sections — with
/// no chrome of its own beyond the pushed app-list picker. Both hosts supply their
/// own navigation bar: the New Rule flow wraps it in `RuleEditorView` (a pushed
/// page with a commit checkmark), and the rule detail sheet embeds it directly,
/// cross-fading between its read-only detail and this form for in-place editing.
/// Binding the draft lets the host own the working copy (and, in the detail sheet,
/// detect outstanding edits for the discard prompt).
struct RuleEditorForm: View {
    @Binding var draft: RuleDraft

    @State private var showingAppPicker = false

    var body: some View {
        Form {
            nameSection
            sections
        }
        // Push the app-list selection onto the host's stack (the back button
        // returns here); the library presents its editor as a sheet.
        .navigationDestination(isPresented: $showingAppPicker) {
            AppListLibraryView(selection: $draft.appList, onPick: { showingAppPicker = false })
                .navigationTitle(CopyKey.ruleEditorAppListTitle.resource)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField(CopyKey.ruleEditorRuleNamePlaceholder.resource, text: $draft.name)
                .submitLabel(.done)
                .accessibilityIdentifier("ruleNameField")
        } header: {
            Text(.ruleEditorNameSectionHeader).textCase(nil)
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch draft.kind {
        case .schedule:
            Section {
                DatePicker(
                    CopyKey.ruleEditorFromLabel.resource,
                    selection: timeBinding($draft.scheduleConfig.startMinutes),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("fromTimePicker")
                DatePicker(
                    CopyKey.ruleEditorToLabel.resource,
                    selection: timeBinding($draft.scheduleConfig.endMinutes),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("toTimePicker")
            } header: {
                Text(.ruleEditorDuringThisTimeHeader).textCase(nil)
            }
            daysSection
            Section {
                Picker(CopyKey.ruleEditorModeLabel.resource, selection: $draft.scheduleConfig.selectionMode) {
                    ForEach(SelectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("selectionModePicker")
                appListRow
            } header: {
                Text(draft.scheduleConfig.selectionMode == .block
                    ? CopyKey.ruleEditorAppsAreBlockedHeader : CopyKey.ruleEditorOnlyTheseAppsAllowedHeader)
                    .textCase(nil)
            }
            hardModeSection
        case .timeLimit:
            Section {
                appListRow
            } header: {
                Text(.ruleEditorWhenIUseHeader).textCase(nil)
            }
            Section {
                budgetRow(
                    value: CopyKey.ruleEditorDailyMinutesAbbreviatedFormat.string(draft.timeLimitConfig.dailyLimitMinutes),
                    accessibilityLabel: CopyKey.ruleEditorDailyTimeLimitAccessibilityLabel.string,
                    accessibilityValue: CopyKey.ruleEditorDailyMinutesAccessibilityFormat.string(draft.timeLimitConfig.dailyLimitMinutes),
                    stepperID: "dailyLimitStepper",
                    onIncrement: {
                        draft.timeLimitConfig.dailyLimitMinutes =
                            min(240, draft.timeLimitConfig.dailyLimitMinutes + 15)
                    },
                    onDecrement: {
                        draft.timeLimitConfig.dailyLimitMinutes =
                            max(15, draft.timeLimitConfig.dailyLimitMinutes - 15)
                    }
                )
            } header: {
                Text(.ruleEditorForThisLongHeader).textCase(nil)
            }
            daysSection
            blockUntilSection
            hardModeSection
        case .openLimit:
            Section {
                appListRow
            } header: {
                Text(.ruleEditorWhenIOpenHeader).textCase(nil)
            }
            Section {
                budgetRow(
                    value: CopyKey.ruleEditorOpensCountFormat.string(draft.openLimitConfig.maxOpens),
                    accessibilityLabel: CopyKey.ruleEditorDailyOpenLimitAccessibilityLabel.string,
                    accessibilityValue: CopyKey.ruleEditorOpensCountFormat.string(draft.openLimitConfig.maxOpens),
                    stepperID: "maxOpensStepper",
                    onIncrement: {
                        draft.openLimitConfig.maxOpens = min(50, draft.openLimitConfig.maxOpens + 1)
                    },
                    onDecrement: {
                        draft.openLimitConfig.maxOpens = max(1, draft.openLimitConfig.maxOpens - 1)
                    }
                )
            } header: {
                Text(.ruleEditorMoreThanHeader).textCase(nil)
            }
            daysSection
            blockUntilSection
            hardModeSection
        }
    }

    private var daysSection: some View {
        Section {
            DayOfWeekPicker(days: $draft.days)
        } header: {
            HStack {
                Text(.ruleEditorOnTheseDaysHeader).textCase(nil)
                Spacer()
                Text(draft.days.summary).textCase(nil)
            }
        }
    }

    private var blockUntilSection: some View {
        Section {
            LabeledContent(CopyKey.ruleEditorUntilLabel.resource, value: CopyKey.ruleEditorTomorrowValue.string)
        } header: {
            Text(.ruleEditorThenBlockAppHeader).textCase(nil)
        }
    }

    /// Hard Mode applies to every kind. A labeled `Toggle` makes the whole row
    /// the tap target and gives VoiceOver a "Hard Mode" switch in one element.
    private var hardModeSection: some View {
        Section {
            Toggle(CopyKey.ruleEditorHardModeToggle.resource, isOn: $draft.hardMode)
                .accessibilityIdentifier("hardModeToggle")
        } footer: {
            Text(.ruleEditorCantPauseWhileActive)
        }
    }

    private var appListRow: some View {
        Button {
            showingAppPicker = true
        } label: {
            HStack {
                Text(.ruleEditorAppListTitle)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(appListLabel)
                    .foregroundStyle(Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .accessibilityIdentifier("selectedAppsRow")
    }

    private var appListLabel: String {
        guard let list = draft.appList else { return CopyKey.ruleEditorChooseAppListPlaceholder.string }
        return CopyKey.ruleEditorAppListSummaryFormat.string(list.name, list.appCountLabel)
    }

    private func budgetRow(
        value: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        stepperID: String,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(.ruleEditorDailyLabel)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(stepperID)Value")
            // The stepper carries its own label + spoken value so VoiceOver
            // announces e.g. "Daily time limit, 45 minutes" as it changes —
            // the adjacent value Text is silent decoration to sighted users.
            Stepper("", onIncrement: onIncrement, onDecrement: onDecrement)
                .labelsHidden()
                .accessibilityIdentifier(stepperID)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
        }
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            let dayStart = Calendar.current.startOfDay(for: .now)
            return Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue, to: dayStart)
                ?? .now
        } set: { newDate in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
            minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }
}
