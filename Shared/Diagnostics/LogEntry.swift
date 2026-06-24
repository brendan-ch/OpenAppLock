//
//  LogEntry.swift
//  OpenAppLock
//

import Foundation

/// Severity of a diagnostic entry. `event` flags the load-bearing
/// "a block/threshold actually fired" lines for easy grepping; it maps to the
/// unified log's `.default` (notice) level.
nonisolated enum LogLevel: String, Sendable, CaseIterable {
    case debug, info, event, error
    /// Upper-cased token used in the line, e.g. `EVENT`.
    var tag: String { rawValue.uppercased() }
}

/// The area a log entry belongs to — both the `os.Logger` category (for Console
/// filtering) and the in-line `[source/category]` tag.
nonisolated enum LogCategory: String, Sendable {
    case enforcer, scheduler, shield, monitor, report
    case usage, dayStart, session, appList, rule, auth, lifecycle
}

/// Which process wrote an entry, inferred from the running bundle so no
/// extension has to wire itself up.
nonisolated enum LogSource: String, Sendable {
    case app
    case monitor
    case shieldConfig = "shieldconfig"
    case shieldAction = "shieldaction"
    case report

    static func current(bundleIdentifier: String?) -> LogSource {
        switch bundleIdentifier {
        case "dev.bchen.OpenAppLock.Monitor": return .monitor
        case "dev.bchen.OpenAppLock.ShieldConfig": return .shieldConfig
        case "dev.bchen.OpenAppLock.ShieldAction": return .shieldAction
        case "dev.bchen.OpenAppLock.Report": return .report
        default: return .app
        }
    }
}

/// Fixed-width UTC ISO8601(ms) timestamps — `2026-06-22T14:03:11.482Z` — so a
/// plain lexical sort of whole lines is chronological. The file's *day bucket*
/// uses the local calendar (`UsageLedger.dayKey`); the per-line stamp is UTC and
/// unambiguous, which is what the merge relies on.
nonisolated enum LogTimestamp {
    static let prefixLength = 24

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    /// The 24-char timestamp prefix used as the merge sort key.
    static func prefix(ofLine line: String) -> String { String(line.prefix(prefixLength)) }
}

/// Builds and parses per-process daily log filenames: `<source>-<YYYY-MM-DD>.log`.
enum LogFilename {
    static let fileExtension = "log"

    static func make(source: String, day: String) -> String {
        "\(source)-\(day).\(fileExtension)"
    }

    /// `monitor-2026-06-22.log` → `(monitor, 2026-06-22)`. Returns nil for any
    /// name that is not a valid log filename (wrong extension, missing source, or
    /// a trailing token that is not a `YYYY-MM-DD` day key).
    static func parse(_ filename: String) -> (source: String, day: String)? {
        let suffix = ".\(fileExtension)"
        guard filename.hasSuffix(suffix) else { return nil }
        let stem = String(filename.dropLast(suffix.count))
        guard stem.count > 11 else { return nil }  // "x-YYYY-MM-DD" is 12+
        let day = String(stem.suffix(10))
        guard isDayKey(day) else { return nil }
        let source = String(stem.dropLast(11))  // drop "-YYYY-MM-DD"
        guard !source.isEmpty else { return nil }
        return (source, day)
    }

    /// True for a `YYYY-MM-DD` all-digit day key.
    static func isDayKey(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
            parts[0].count == 4, parts[1].count == 2, parts[2].count == 2
        else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

/// One diagnostic record. `formatted` is the canonical single-line rendering
/// written to the per-process file and shown on export. Every entry carries the
/// source location (`file:line function`) it was emitted from, so a line read
/// back from an exported log can be traced straight to the code that produced it.
nonisolated struct LogEntry: Sendable {
    let date: Date
    let level: LogLevel
    let source: LogSource
    let category: LogCategory
    let message: String
    /// Short source file name, e.g. `RuleEnforcer.swift` (see ``shortFile(_:)``).
    let file: String
    /// Source line the entry was emitted from.
    let line: Int
    /// Enclosing function, e.g. `refresh(rules:at:calendar:)`.
    let function: String

    /// `<iso> [LEVEL] [source/category] message [File.swift:line function]`.
    /// The 24-char UTC timestamp stays the line's prefix (the merge sort key);
    /// the trailing bracket is the code anchor.
    var formatted: String {
        "\(LogTimestamp.string(from: date)) [\(level.tag)] "
            + "[\(source.rawValue)/\(category.rawValue)] \(Self.sanitize(message)) "
            + "[\(file):\(line) \(Self.sanitize(function))]"
    }

    /// Collapses newlines and tabs to spaces so each entry stays exactly one line.
    static func sanitize(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    /// Reduces a `#fileID` (`Module/Path/File.swift`) to just `File.swift`, which
    /// is what identifies the code site (filenames are unique in this project) and
    /// stays stable across the targets a `Shared/` file compiles into.
    static func shortFile(_ fileID: String) -> String {
        String(fileID.split(separator: "/").last ?? Substring(fileID))
    }
}
