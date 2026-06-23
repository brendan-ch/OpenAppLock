//
//  DiagnosticLog.swift
//  OpenAppLock
//

import Foundation
import os

/// Consistent diagnostic logging shared by the app and every Screen Time
/// extension. Each call writes to **two sinks**: the unified log (`os.Logger`,
/// for live viewing in Xcode/Console, filterable by category) and a persisted
/// per-process daily file in the app group (for export from Settings). On iOS
/// `OSLogStore` can only read the current process, so the file is the only way
/// to assemble one timeline across all five processes.
///
/// Always-on, `nonisolated`, and thread-safe: callable from any process or queue
/// (extension callbacks run on arbitrary threads; the app target defaults to
/// `MainActor`). Every entry records its source location so a logged line traces
/// back to the exact code. See `Docs/Agents/Specs/DIAGNOSTIC_LOGGING.md`.
enum Diag {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var writer: LogFileWriter?
    nonisolated(unsafe) private static var loggers: [LogCategory: Logger] = [:]
    private static let subsystem = "dev.bchen.OpenAppLock"

    /// The process this build is running as, inferred once from the bundle id.
    static let source = LogSource.current(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// Points the persisted sink at `directory`. The app calls this once at
    /// launch (app-group `Logs/` in production, a temp dir under UI testing).
    /// Extensions never call it and fall back to the app-group directory on first
    /// use. `source` defaults to the inferred process; tests pass it explicitly.
    nonisolated static func configure(directory: URL, source: LogSource = Diag.source) {
        lock.lock()
        defer { lock.unlock() }
        writer = LogFileWriter(directory: directory, source: source)
    }

    nonisolated static func log(
        _ category: LogCategory, _ level: LogLevel = .info, _ message: String,
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        let date = Date()
        let shortFile = LogEntry.shortFile(file)
        let entry = LogEntry(
            date: date, level: level, source: source, category: category, message: message,
            file: shortFile, line: line, function: function)
        logger(for: category).log(
            level: level.osType, "\(message, privacy: .public) [\(shortFile):\(line)]")
        fileWriter().append(entry.formatted, day: date)
    }

    nonisolated static func error(
        _ category: LogCategory, _ message: String,
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        log(category, .error, message, file: file, function: function, line: line)
    }

    nonisolated private static func fileWriter() -> LogFileWriter {
        lock.lock()
        defer { lock.unlock() }
        if let writer { return writer }
        let created = LogFileWriter(
            directory: DiagnosticLogLocation.defaultDirectory(), source: source)
        writer = created
        return created
    }

    nonisolated private static func logger(for category: LogCategory) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let existing = loggers[category] { return existing }
        let created = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = created
        return created
    }
}

extension LogLevel {
    /// Mapping to unified-log severities. `event` → `.default` (notice).
    var osType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .event: return .default
        case .error: return .error
        }
    }
}
