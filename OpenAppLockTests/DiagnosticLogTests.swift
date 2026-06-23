//
//  DiagnosticLogTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
struct DiagnosticLogTests {
    /// A fixed instant: 2026-06-22 14:03:11.482 UTC (built in the UTC test
    /// calendar so the rendered timestamp is deterministic everywhere).
    private var fixedDate: Date {
        date(2026, 6, 22, 14, 3).addingTimeInterval(11.482)
    }

    @Test("Entry renders one sortable line with UTC ms timestamp and code site")
    func entryLine() {
        let entry = LogEntry(
            date: fixedDate, level: .event, source: .app, category: .enforcer,
            message: "refresh: applied rule-ABC", file: "RuleEnforcer.swift", line: 104,
            function: "refresh(rules:at:calendar:)")
        #expect(
            entry.formatted
                == "2026-06-22T14:03:11.482Z [EVENT] [app/enforcer] refresh: applied rule-ABC "
                    + "[RuleEnforcer.swift:104 refresh(rules:at:calendar:)]")
    }

    @Test("Message newlines and tabs are flattened so an entry stays one line")
    func sanitize() {
        let entry = LogEntry(
            date: fixedDate, level: .info, source: .monitor, category: .monitor,
            message: "line1\nline2\tcol\r\nline3", file: "Monitor.swift", line: 9,
            function: "f()")
        #expect(!entry.formatted.dropFirst(LogTimestamp.prefixLength).contains("\n"))
        #expect(entry.formatted.contains("line1 line2 col line3"))
    }

    @Test("Short file name keeps only the file component of a #fileID")
    func shortFile() {
        #expect(LogEntry.shortFile("OpenAppLock/RuleEnforcer.swift") == "RuleEnforcer.swift")
        #expect(LogEntry.shortFile("Bare.swift") == "Bare.swift")
    }

    @Test("Source is inferred from the bundle identifier suffix")
    func sourceInference() {
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock") == .app)
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.Monitor") == .monitor)
        #expect(
            LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.ShieldConfig")
                == .shieldConfig)
        #expect(
            LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.ShieldAction")
                == .shieldAction)
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.Report") == .report)
        #expect(LogSource.current(bundleIdentifier: nil) == .app)
        #expect(LogSource.current(bundleIdentifier: "com.example.other") == .app)
    }

    @Test("Filename round-trips source and day; rejects non-log names")
    func filename() {
        #expect(LogFilename.make(source: "app", day: "2026-06-22") == "app-2026-06-22.log")
        let parsed = LogFilename.parse("monitor-2026-06-22.log")
        #expect(parsed?.source == "monitor")
        #expect(parsed?.day == "2026-06-22")
        #expect(LogFilename.parse("notes.txt") == nil)
        #expect(LogFilename.parse("2026-06-22.log") == nil)  // no source
        #expect(LogFilename.parse("app-not-a-date.log") == nil)
    }

    @Test("Timestamp prefix of a line equals the rendered timestamp")
    func timestampPrefix() {
        let entry = LogEntry(
            date: fixedDate, level: .debug, source: .report, category: .report, message: "x",
            file: "Report.swift", line: 1, function: "f()")
        #expect(LogTimestamp.prefix(ofLine: entry.formatted) == "2026-06-22T14:03:11.482Z")
    }
}
