//
//  LogStoreTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
struct LogStoreTests {
    private func makeDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ name: String, _ lines: [String], in dir: URL) throws {
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test("Available days list newest-first with line counts, ignoring non-logs")
    func availableDays() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("app-2026-06-20.log", ["2026-06-20T01:00:00.000Z [INFO] [app/rule] a"], in: dir)
        try write(
            "app-2026-06-22.log",
            [
                "2026-06-22T01:00:00.000Z [INFO] [app/rule] b",
                "2026-06-22T02:00:00.000Z [INFO] [app/rule] c",
            ], in: dir)
        try write(
            "monitor-2026-06-22.log",
            ["2026-06-22T01:30:00.000Z [EVENT] [monitor/monitor] m"], in: dir)
        try write("README.txt", ["ignore me"], in: dir)

        let store = LogStore(directory: dir, calendar: utc)
        let days = store.availableDays()
        #expect(days.map(\.key) == ["2026-06-22", "2026-06-20"])
        #expect(days[0].lineCount == 3)  // 2 app + 1 monitor
        #expect(days[1].lineCount == 1)
    }

    @Test("Merged text for a day interleaves all sources chronologically")
    func mergedText() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(
            "app-2026-06-22.log",
            [
                "2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1",
                "2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2",
            ], in: dir)
        try write(
            "monitor-2026-06-22.log",
            ["2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1"], in: dir)

        let store = LogStore(directory: dir, calendar: utc)
        let text = store.mergedText(for: "2026-06-22")
        #expect(
            text == """
                2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1
                2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1
                2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2
                """)
    }

    @Test("Export writes the merged text to a .txt file named for the day")
    func exportFile() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write(
            "app-2026-06-22.log", ["2026-06-22T10:00:00.000Z [INFO] [app/rule] only"], in: dir)
        let store = LogStore(directory: dir, calendar: utc)
        let url = try store.exportFile(for: "2026-06-22")
        #expect(url.lastPathComponent == "OpenAppLock-logs-2026-06-22.txt")
        let exported = try String(contentsOf: url, encoding: .utf8)
        #expect(exported.contains("only"))
    }

    @Test("Clear removes every log file")
    func clearAll() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("app-2026-06-22.log", ["x"], in: dir)
        try write("monitor-2026-06-22.log", ["y"], in: dir)
        let store = LogStore(directory: dir, calendar: utc)
        store.clearAll()
        #expect(store.availableDays().isEmpty)
    }

    @Test("Prune deletes only files older than the retention window")
    func prune() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("app-2026-06-22.log", ["keep"], in: dir)
        try write("app-2026-05-01.log", ["old"], in: dir)
        let store = LogStore(directory: dir, calendar: utc)
        store.prune(today: date(2026, 6, 22), retentionDays: 14)
        #expect(store.availableDays().map(\.key) == ["2026-06-22"])
    }
}
