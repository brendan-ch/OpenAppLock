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

@MainActor
struct LogMergeRetentionTests {
    @Test("Merge interleaves files chronologically by the UTC prefix")
    func mergeChronological() {
        let app = [
            "2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1",
            "2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2",
        ]
        let monitor = [
            "2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1"
        ]
        let merged = LogMerge.merge(perFile: [app, monitor])
        #expect(
            merged == [
                "2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1",
                "2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1",
                "2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2",
            ])
    }

    @Test("Equal timestamps keep file order, then within-file order (stable)")
    func mergeStableTies() {
        let fileA = [
            "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-first",
            "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-second",
        ]
        let fileB = ["2026-06-22T10:00:00.000Z [INFO] [monitor/usage] B-first"]
        let merged = LogMerge.merge(perFile: [fileA, fileB])
        #expect(
            merged == [
                "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-first",
                "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-second",
                "2026-06-22T10:00:00.000Z [INFO] [monitor/usage] B-first",
            ])
    }

    @Test("Prune selects files strictly older than the retention window")
    func prune() {
        let today = date(2026, 6, 22)  // from TestSupport (UTC calendar)
        let names = [
            "app-2026-06-22.log",  // today — keep
            "app-2026-06-08.log",  // 14 days ago — keep (boundary)
            "monitor-2026-06-07.log",  // 15 days ago — prune
            "app-2026-05-01.log",  // old — prune
            "notes.txt",  // not a log — ignored
        ]
        let pruned = Set(
            LogRetention.filesToPrune(
                filenames: names, today: today, retentionDays: 14, calendar: utc))
        #expect(pruned == ["monitor-2026-06-07.log", "app-2026-05-01.log"])
    }
}
