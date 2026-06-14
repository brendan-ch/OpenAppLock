//
//  RuleEditorView.swift
//  OpenAppLock
//

import SwiftUI

/// The rule editor as a plain Form, always pushed inside a NavigationStack
/// (New Rule flow and detail editing both push it). Both modes commit via a
/// checkmark confirmation button in the navigation bar; edit mode adds an
/// ellipsis "Rule Actions" menu (Disable/Enable, Delete) next to it.
struct RuleEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(isEnabled: Bool)
    }

    let mode: Mode
    @State var draft: RuleDraft
    var onCommit: (RuleDraft) -> Void
    var onToggleEnabled: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var showingAppPicker = false

    var body: some View {
        Form {
            nameSection
            sections
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(draft.sanitized().name)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityIdentifier("ruleEditorTitle")
            }
            if case .edit(let isEnabled) = mode {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(isEnabled ? "Disable Rule" : "Enable Rule") {
                            onToggleEnabled?()
                        }
                        Button("Delete Rule", role: .destructive) {
                            onDelete?()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Rule Actions")
                    .accessibilityIdentifier("ruleActionsMenu")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                switch mode {
                case .create:
                    Button(role: .confirm) {
                        onCommit(draft.sanitized())
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Add Rule")
                    .accessibilityIdentifier("commitRuleButton")
                case .edit:
                    Button(role: .confirm) {
                        onCommit(draft.sanitized())
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Done")
                    .accessibilityIdentifier("doneButton")
                }
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppListPickerSheet(selected: $draft.appList)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Rule Name", text: $draft.name)
                .submitLabel(.done)
                .accessibilityIdentifier("ruleNameField")
        } header: {
            Text("Name").textCase(nil)
        }
    }

    @ViewBuilder
    private var sections: some View {
        switch draft.kind {
        case .schedule:
            Section {
                DatePicker(
                    "From",
                    selection: timeBinding($draft.scheduleConfig.startMinutes),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("fromTimePicker")
                DatePicker(
                    "To",
                    selection: timeBinding($draft.scheduleConfig.endMinutes),
                    displayedComponents: .hourAndMinute
                )
                .accessibilityIdentifier("toTimePicker")
            } header: {
                Text("During this time").textCase(nil)
            }
            daysSection
            Section {
                Picker("Mode", selection: $draft.scheduleConfig.selectionMode) {
                    ForEach(SelectionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("selectionModePicker")
                appListRow
            } header: {
                Text(draft.scheduleConfig.selectionMode == .block
                    ? "Apps are blocked" : "Only these apps are allowed")
                    .textCase(nil)
            }
            hardModeSection
            // Block Adult Content is a Schedule-only option: a usage budget
            // does not pair with a web-content filter (see spec §1).
            adultContentSection
        case .timeLimit:
            Section {
                appListRow
            } header: {
                Text("When I use").textCase(nil)
            }
            Section {
                budgetRow(
                    value: "\(draft.timeLimitConfig.dailyLimitMinutes)m",
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
                Text("For this long").textCase(nil)
            }
            daysSection
            blockUntilSection
            hardModeSection
        case .openLimit:
            Section {
                appListRow
            } header: {
                Text("When I open").textCase(nil)
            }
            Section {
                budgetRow(
                    value: "\(draft.openLimitConfig.maxOpens) opens",
                    stepperID: "maxOpensStepper",
                    onIncrement: {
                        draft.openLimitConfig.maxOpens = min(50, draft.openLimitConfig.maxOpens + 1)
                    },
                    onDecrement: {
                        draft.openLimitConfig.maxOpens = max(1, draft.openLimitConfig.maxOpens - 1)
                    }
                )
            } header: {
                Text("More than").textCase(nil)
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
                Text("On these days").textCase(nil)
                Spacer()
                Text(draft.days.summary).textCase(nil)
            }
        }
    }

    private var blockUntilSection: some View {
        Section {
            LabeledContent("Until", value: "Tomorrow")
        } header: {
            Text("Then block app").textCase(nil)
        }
    }

    /// Hard Mode applies to every kind.
    private var hardModeSection: some View {
        Section {
            HStack {
                Text("Hard Mode")
                Spacer()
                Toggle("", isOn: $draft.hardMode)
                    .labelsHidden()
                    .accessibilityIdentifier("hardModeToggle")
            }
        } footer: {
            Text("No unblocks allowed while the rule is blocking.")
        }
    }

    /// Schedule-only: filter adult websites while the rule's window is active.
    private var adultContentSection: some View {
        Section {
            HStack {
                Text("Block Adult Content")
                Spacer()
                Toggle("", isOn: $draft.scheduleConfig.blockAdultContent)
                    .labelsHidden()
                    .accessibilityIdentifier("adultContentToggle")
            }
        } footer: {
            Text("Filter adult websites while this rule is active.")
        }
    }

    private var appListRow: some View {
        Button {
            showingAppPicker = true
        } label: {
            HStack {
                Text("App List")
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
        guard let list = draft.appList else { return "Choose" }
        return "\(list.name) · \(list.appCountLabel)"
    }

    private func budgetRow(
        value: String,
        stepperID: String,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void
    ) -> some View {
        HStack {
            Text("Daily")
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(stepperID)Value")
            Stepper("", onIncrement: onIncrement, onDecrement: onDecrement)
                .labelsHidden()
                .accessibilityIdentifier(stepperID)
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
