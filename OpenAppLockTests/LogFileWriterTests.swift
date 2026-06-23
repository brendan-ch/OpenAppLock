//
//  LogFileWriterTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
struct LogFileWriterTests {
    /// A unique empty temp directory for one test.
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Appends accumulate into the source+day file, newline-separated")
    func appendsAccumulate() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = date(2026, 6, 22)
        let writer = LogFileWriter(directory: dir, source: .app, calendar: utc)

        writer.append("2026-06-22T10:00:00.000Z [INFO] [app/enforcer] one", day: day)
        writer.append("2026-06-22T10:00:01.000Z [INFO] [app/enforcer] two", day: day)

        let fileURL = dir.appendingPathComponent("app-2026-06-22.log")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(
            contents == """
                2026-06-22T10:00:00.000Z [INFO] [app/enforcer] one
                2026-06-22T10:00:01.000Z [INFO] [app/enforcer] two

                """)
    }

    @Test("Different days write to different files")
    func dayBuckets() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = LogFileWriter(directory: dir, source: .monitor, calendar: utc)
        writer.append("x", day: date(2026, 6, 22))
        writer.append("y", day: date(2026, 6, 23))

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(names == ["monitor-2026-06-22.log", "monitor-2026-06-23.log"])
    }

    @Test("Creates the directory if it does not exist yet")
    func createsDirectory() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let nested = parent.appendingPathComponent("Logs", isDirectory: true)
        let writer = LogFileWriter(directory: nested, source: .report, calendar: utc)
        writer.append("hello", day: date(2026, 6, 22))
        #expect(
            FileManager.default.fileExists(
                atPath: nested.appendingPathComponent("report-2026-06-22.log").path))
    }
}

@MainActor
struct DiagFacadeTests {
    @Test("Configured Diag writes a parseable line to the source file")
    func diagWritesLine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagFacade-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        Diag.configure(directory: dir, source: .app)
        Diag.log(.enforcer, .event, "refresh: applied rule-XYZ")

        // The file name carries today's local day key.
        let dayKey = UsageLedger.dayKey(for: .now)
        let fileURL = dir.appendingPathComponent("app-\(dayKey).log")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(contents.contains("[EVENT] [app/enforcer] refresh: applied rule-XYZ"))
        // The line starts with a 24-char UTC timestamp and ends with a code site.
        let firstLine = contents.split(separator: "\n").first.map(String.init) ?? ""
        #expect(LogTimestamp.prefix(ofLine: firstLine).hasSuffix("Z"))
        #expect(firstLine.contains("[LogFileWriterTests.swift:"))
    }
}
