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
                    Text("No logs yet. Logs are recorded automatically as rules enforce.")
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
                                Text("^[\(day.lineCount) line](inflect: true)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("logDayRow-\(day.key)")
                    }
                } header: {
                    Text("Days").textCase(nil)
                } footer: {
                    Text(
                        "Each day merges the app and all Screen Time extensions, oldest entries "
                            + "first. Logs older than 14 days are removed automatically.")
                }
                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("Clear All Logs")
                    }
                    .accessibilityIdentifier("clearLogsButton")
                    .confirmationDialog(
                        "Clear all logs?", isPresented: $showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All Logs", role: .destructive) {
                            logStore.clearAll()
                            days = logStore.availableDays()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This permanently deletes all recorded diagnostic logs on this device.")
                    }
                }
            }
        }
        .navigationTitle("Logs")
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
            Text(text.isEmpty ? "No entries." : text)
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
        "2026-06-22T09:00:01.140Z [EVENT] [app/shield] apply rule-1A2B mode=block adult=false [ShieldController.swift:63 applyShield(ruleID:selectionData:mode:blockAdultContent:)]",
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
