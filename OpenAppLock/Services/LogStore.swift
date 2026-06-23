//
//  LogStore.swift
//  OpenAppLock
//

import Foundation
import Observation

/// App-side read access to the persisted diagnostic logs: lists the days that
/// have logs, merges all per-process files for a day into one chronological
/// blob, exports that blob as a temp `.txt` for `ShareLink`, clears everything,
/// and prunes aged-out days at launch. Backed by the same directory `Diag` writes
/// to (app-group `Logs/` in production, a temp dir under UI testing).
@Observable
final class LogStore {
    private let directory: URL
    private let calendar: Calendar
    private let fileManager = FileManager.default

    init(
        directory: URL = DiagnosticLogLocation.defaultDirectory(), calendar: Calendar = .current
    ) {
        self.directory = directory
        self.calendar = calendar
    }

    /// A day that has at least one log line, with totals for the list subtitle.
    struct Day: Identifiable, Equatable {
        let key: String
        let lineCount: Int
        let byteCount: Int
        var id: String { key }
    }

    /// Days with logs, newest first.
    func availableDays() -> [Day] {
        var byDay: [String: (lines: Int, bytes: Int)] = [:]
        for name in logFilenames() {
            guard let parsed = LogFilename.parse(name) else { continue }
            let url = directory.appendingPathComponent(name)
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).count
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let bytes = (attributes?[.size] as? Int) ?? 0
            let running = byDay[parsed.day] ?? (0, 0)
            byDay[parsed.day] = (running.lines + lines, running.bytes + bytes)
        }
        return
            byDay
            .map { Day(key: $0.key, lineCount: $0.value.lines, byteCount: $0.value.bytes) }
            .sorted { $0.key > $1.key }
    }

    /// All sources for `dayKey`, merged chronologically and joined by newlines.
    func mergedText(for dayKey: String) -> String {
        let perFile: [[String]] =
            logFilenames()
            .filter { LogFilename.parse($0)?.day == dayKey }
            .sorted()
            .map { name in
                let url = directory.appendingPathComponent(name)
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            }
        return LogMerge.merge(perFile: perFile).joined(separator: "\n")
    }

    /// Writes the merged day to a temp `OpenAppLock-logs-<day>.txt` and returns it.
    func exportFile(for dayKey: String) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("OpenAppLock-logs-\(dayKey).txt")
        try mergedText(for: dayKey).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Deletes every log file.
    func clearAll() {
        for name in logFilenames() {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Deletes files whose day is older than `retentionDays`. Called at launch.
    func prune(today: Date = .now, retentionDays: Int = 14) {
        let stale = LogRetention.filesToPrune(
            filenames: logFilenames(), today: today, retentionDays: retentionDays,
            calendar: calendar)
        for name in stale {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func logFilenames() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    }
}
