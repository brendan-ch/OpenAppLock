//
//  LogFileWriter.swift
//  OpenAppLock
//

import Foundation

/// Where persisted logs live: `Logs/` inside the shared app-group container, so
/// every process writes to the same place and the app can read them all back.
/// Falls back to the temp directory if the group container is unavailable (e.g.
/// the entitlement is not provisioned yet).
enum DiagnosticLogLocation {
    static func defaultDirectory() -> URL {
        let base =
            FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Logs", isDirectory: true)
    }
}

/// Appends one process's log lines to its own per-day file
/// (`<source>-<YYYY-MM-DD>.log`). Per-process files mean no cross-process write
/// contention; a private serial queue plus an open→seek-end→write→close per line
/// keeps writes ordered and durable even if an extension is killed right after.
final class LogFileWriter: @unchecked Sendable {
    private let directory: URL
    private let source: LogSource
    private let calendar: Calendar
    private let queue: DispatchQueue
    private let fileManager = FileManager.default

    init(directory: URL, source: LogSource, calendar: Calendar = .current) {
        self.directory = directory
        self.source = source
        self.calendar = calendar
        self.queue = DispatchQueue(label: "dev.bchen.OpenAppLock.log.\(source.rawValue)")
    }

    /// Appends `line` (a single, newline-free record) to the file for `day`.
    /// Synchronous so an extension never returns before its last line is on disk.
    func append(_ line: String, day: Date) {
        queue.sync {
            let dayKey = UsageLedger.dayKey(for: day, calendar: calendar)
            let url = directory.appendingPathComponent(
                LogFilename.make(source: source.rawValue, day: dayKey))
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                // File does not exist yet — create it with the first line.
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
