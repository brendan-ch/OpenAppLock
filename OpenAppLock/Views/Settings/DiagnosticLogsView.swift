//
//  DiagnosticLogsView.swift
//  OpenAppLock
//

import SwiftUI

/// Settings → Diagnostics → Logs. Lists the days that have diagnostic logs and
/// drills into a per-day, merged, exportable view. The logs capture how and when
/// blocks execute across the app and its Screen Time extensions (see
/// `Docs/Agents/Specs/DIAGNOSTIC_LOGGING.md`); export hands a day's `.txt` to the
/// share sheet so it can be sent off for debugging.
struct DiagnosticLogsView: View {
    @Environment(LogStore.self) private var logStore
    @State private var days: [LogStore.Day] = []
    @State private var showClearConfirmation = false

    var body: some View {
        List {
            if days.isEmpty {
                Section {
                    Text(.diagnosticsNoLogsMessage)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("noLogsLabel")
                }
            } else {
                Section {
                    ForEach(days) { day in
                        NavigationLink {
                            LogDayDetailView(dayKey: day.key)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.key)
                                // Out of scope for the catalog migration: SwiftUI's
                                // `^[...](inflect: true)` automatic grammar agreement
                                // requires compile-time string interpolation and has
                                // no equivalent in `CopyKey.string(_:)`'s
                                // `String(format:)` resolution; moving it would
                                // either lose correct singular/plural inflection or
                                // require plural-variation catalog support, which the
                                // migration's design spec explicitly rules out
                                // (`Docs/Agents/Specs/COPY_STRING_CATALOG_MIGRATION.md`,
                                // "Out of scope: Pluralization overhaul").
                                Text("^[\(day.lineCount) line](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("logDayRow-\(day.key)")
                    }
                } header: {
                    Text(.diagnosticsDaysSectionHeader).textCase(nil)
                } footer: {
                    Text(.diagnosticsDaysSectionFooter)
                }
                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text(.diagnosticsClearAllLogsButton)
                    }
                    .accessibilityIdentifier("clearLogsButton")
                    .confirmationDialog(
                        CopyKey.diagnosticsClearLogsConfirmationTitle.resource,
                        isPresented: $showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(CopyKey.diagnosticsClearAllLogsButton.resource, role: .destructive) {
                            logStore.clearAll()
                            days = logStore.availableDays()
                        }
                        Button(CopyKey.diagnosticsCancelButton.resource, role: .cancel) {}
                    } message: {
                        Text(.diagnosticsClearLogsConfirmationMessage)
                    }
                }
            }
        }
        .navigationTitle(CopyKey.diagnosticsNavigationTitle.resource)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { days = logStore.availableDays() }
    }
}

/// One day's merged log: a scrollable monospaced dump plus a share/export action.
struct LogDayDetailView: View {
    @Environment(LogStore.self) private var logStore
    let dayKey: String

    private var text: String { logStore.mergedText(for: dayKey) }

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? CopyKey.diagnosticsNoEntriesPlaceholder.string : text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
                .accessibilityIdentifier("logDayText")
        }
        .navigationTitle(dayKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let url = try? logStore.exportFile(for: dayKey) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportLogButton")
                }
            }
        }
    }
}

/// A `LogStore` over a fresh temp directory seeded with two days of sample
/// lines, for previews.
private func previewLogStore() -> LogStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DiagPreview-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let today = UsageLedger.dayKey(for: .now)
    let earlier = UsageLedger.dayKey(
        for: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
    let app = [
        "2026-06-22T09:00:01.120Z [INFO] [app/enforcer] refresh: 2 rules [RuleEnforcer.swift:84 refresh(rules:at:calendar:)]",
        "2026-06-22T09:00:01.140Z [EVENT] [app/shield] apply rule-1A2B mode=block [ShieldController.swift:61 applyShield(ruleID:selectionData:mode:)]",
    ]
    let monitor = [
        "2026-06-22T09:14:55.300Z [EVENT] [monitor/monitor] eventDidReachThreshold minutes-15 [DeviceActivityMonitorExtension.swift:40 eventDidReachThreshold(_:activity:)]"
    ]
    try? (app.joined(separator: "\n") + "\n").write(
        to: dir.appendingPathComponent("app-\(today).log"), atomically: true, encoding: .utf8)
    try? (monitor.joined(separator: "\n") + "\n").write(
        to: dir.appendingPathComponent("monitor-\(today).log"), atomically: true, encoding: .utf8)
    try? "2026-06-21T22:30:00.000Z [INFO] [app/lifecycle] app launch [OpenAppLockApp.swift:41 init()]\n"
        .write(
            to: dir.appendingPathComponent("app-\(earlier).log"), atomically: true,
            encoding: .utf8)
    return LogStore(directory: dir)
}

#Preview("Logs — populated") {
    NavigationStack {
        DiagnosticLogsView()
    }
    .environment(previewLogStore())
}

#Preview("Log day — detail") {
    let store = previewLogStore()
    return NavigationStack {
        LogDayDetailView(dayKey: UsageLedger.dayKey(for: .now))
    }
    .environment(store)
}

#Preview("Logs — empty") {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("DiagPreviewEmpty-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return NavigationStack {
        DiagnosticLogsView()
    }
    .environment(LogStore(directory: dir))
}
