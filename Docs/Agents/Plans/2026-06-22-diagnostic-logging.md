# Diagnostic Logging & Daily Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a consistent, always-on logging system that every OpenAppLock process (app + four Screen Time extensions) writes to, viewable live in Xcode/Console and exportable from Settings as a per-day `.txt` file.

**Architecture:** A dual-sink logger in `Shared/` — every `Diag.log(...)` writes to `os.Logger` (live) and appends one line to a per-process daily file in the app-group container (`Logs/<source>-<YYYY-MM-DD>.log`). The app's `LogStore` merges all per-process files for a chosen day by timestamp and hands a temp `.txt` to a SwiftUI `ShareLink`. Per-process files avoid cross-process write corruption; merge happens only at export time.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `os` unified logging, `FileHandle`, Swift Testing (`import Testing`), XCUITest. Build/test via the **Xcode MCP** tools (`BuildProject`, `RunSomeTests`, `RunAllTests`) — never raw `xcodebuild`.

## Global Constraints

- **Always-on** logging in every build; Settings exposes Export + Clear only (no enable/disable toggle).
- **14-day** on-device retention, pruned at app launch.
- App-group identifier is `group.dev.bchen.OpenAppLock` (`AppGroup.identifier`).
- Bundle IDs → source: `dev.bchen.OpenAppLock`→`app`, `.Monitor`→`monitor`, `.ShieldConfig`→`shieldconfig`, `.ShieldAction`→`shieldaction`, `.Report`→`report`.
- Line format (one entry per line): `<UTC-ISO8601-ms> [<LEVEL>] [<source>/<category>] <message> [<File.swift>:<line> <function>]`, e.g. `2026-06-22T14:03:11.482Z [EVENT] [app/enforcer] applied shield rule-ABC [RuleEnforcer.swift:104 refresh(rules:at:calendar:)]`. The timestamp is **UTC** (sortable); the **file's day bucket uses the local calendar** (`UsageLedger.dayKey`). Every entry carries its **source location** (`#fileID`/`#line`/`#function`) so a log line traces back to the exact code.
- **Verbosity:** the enforcement sites log inputs, the decision, and the outcome — including the "why-not" branches (rule considered but not shielded and why; usage/threshold event rejected as stale; before→after shield state per refresh; whether a save re-enforced). Reading a day back must show exactly what happened and let anomalies be traced to code.
- Levels: `debug · info · event · error` (`event` → `os` `.default`/notice).
- Logging is strictly **additive** — it must never change behavior. The full existing unit + UI suites must stay green.
- Logging types are `Sendable` / `nonisolated` — callable from any process/thread (the app target defaults to `MainActor` isolation; extensions call from arbitrary queues). Do **not** hop to `MainActor`.
- Swift style: `let` over `var`; small focused files; reuse `UsageLedger.dayKey(for:calendar:)` for day-bucket keys (DRY).
- Tests live in `OpenAppLockTests/` (unit, `@MainActor`, Swift Testing) and `OpenAppLockUITests/` (XCUITest). Unit tests must build their own values; no SwiftData container churn needed for the logging types (they're plain values + temp-dir files).
- The project uses file-system-synchronized Xcode groups: adding a `.swift` file on disk is enough (no `.pbxproj` edits) **as long as the file is inside a folder already in the target's membership**. `Shared/*.swift` compiles into the app + all four extensions; `OpenAppLock/**` into the app; `OpenAppLockTests/**` / `OpenAppLockUITests/**` into the test bundles. New files go in those existing folders so membership is automatic.

---

## File map

| File | Responsibility |
|---|---|
| `Shared/LogEntry.swift` (new) | `LogLevel`, `LogCategory`, `LogSource`, `LogTimestamp`, `LogFilename`, `LogEntry` (+ `.line`) — pure value types & formatting |
| `Shared/LogMerge.swift` (new) | `LogMerge.merge(perFile:)` — stable chronological merge |
| `Shared/LogRetention.swift` (new) | `LogRetention.filesToPrune(...)` — age-based prune selection |
| `Shared/LogFileWriter.swift` (new) | `DiagnosticLogLocation`, `LogFileWriter` — per-process serial append |
| `Shared/DiagnosticLog.swift` (new) | `Diag` facade: os.Logger + writer wiring, `configure`, source inference |
| `OpenAppLock/Services/LogStore.swift` (new) | App-side read / list-days / merge-text / export / clear / prune |
| `OpenAppLock/Views/Settings/DiagnosticLogsView.swift` (new) | Days list → day detail → ShareLink + Clear |
| `OpenAppLock/Views/Settings/SettingsView.swift` (modify) | Add Diagnostics section row |
| `OpenAppLock/Services/LaunchConfiguration.swift` (modify) | `-seed-logs` flag + `seedLogs` field |
| `OpenAppLock/OpenAppLockApp.swift` (modify) | Configure `Diag`, prune at launch, inject `LogStore`, route + seed under UI-testing |
| Instrumentation sites (modify) | `RuleEnforcer`, `ManagedSettingsShieldController`, `RuleScheduler`, monitor/report/shield-action extensions, `LimitEnforcement`, `UsageLedger`, `DayStartStore`, `OpenSessionStore`, app-list/rule save |
| `OpenAppLockTests/DiagnosticLogTests.swift` (new) | Unit: formatting, sanitize, source, filename, merge, retention |
| `OpenAppLockTests/LogFileWriterTests.swift` (new) | Unit: writer round-trip + Diag end-to-end in temp dir |
| `OpenAppLockTests/LogStoreTests.swift` (new) | Unit: list/merge/export/clear/prune in temp dir |
| `OpenAppLockTests/LaunchSupportTests.swift` (modify) | Unit: `-seed-logs` parsing |
| `OpenAppLockUITests/DiagnosticLogsUITests.swift` (new) | Flow: seed → navigate → assert → clear |

---

## Task 1: Core log value types & formatting

**Files:**
- Create: `Shared/LogEntry.swift`
- Test: `OpenAppLockTests/DiagnosticLogTests.swift`

**Interfaces:**
- Produces:
  - `enum LogLevel: String, Sendable, CaseIterable { case debug, info, event, error; var tag: String }`
  - `enum LogCategory: String, Sendable { case enforcer, scheduler, shield, monitor, report, usage, dayStart, session, appList, rule, auth, lifecycle }`
  - `enum LogSource: String, Sendable { case app, monitor, shieldConfig, shieldAction, report; static func current(bundleIdentifier: String?) -> LogSource }`
  - `enum LogTimestamp { static func string(from: Date) -> String; static func prefix(ofLine: String) -> String; static let prefixLength: Int }`
  - `enum LogFilename { static func make(source: String, day: String) -> String; static func parse(_:) -> (source: String, day: String)?; static func isDayKey(_:) -> Bool }`
  - `struct LogEntry: Sendable { let date: Date; let level: LogLevel; let source: LogSource; let category: LogCategory; let message: String; var line: String; static func sanitize(_:) -> String }`

- [ ] **Step 1: Write the failing tests**

Create `OpenAppLockTests/DiagnosticLogTests.swift`:

```swift
//
//  DiagnosticLogTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

@MainActor
struct DiagnosticLogTests {
    /// A fixed instant: 2026-06-22 14:03:11.482 UTC.
    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_781_186_591.482)
    }

    @Test("Entry renders one sortable line with UTC ms timestamp")
    func entryLine() {
        let entry = LogEntry(
            date: fixedDate, level: .event, source: .app, category: .enforcer,
            message: "refresh: applied rule-ABC")
        #expect(entry.line == "2026-06-22T14:03:11.482Z [EVENT] [app/enforcer] refresh: applied rule-ABC")
    }

    @Test("Message newlines and tabs are flattened so an entry stays one line")
    func sanitize() {
        let entry = LogEntry(
            date: fixedDate, level: .info, source: .monitor, category: .monitor,
            message: "line1\nline2\tcol\r\nline3")
        #expect(!entry.line.dropFirst(LogTimestamp.prefixLength).contains("\n"))
        #expect(entry.line.hasSuffix("line1 line2 col  line3"))
    }

    @Test("Source is inferred from the bundle identifier suffix")
    func sourceInference() {
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock") == .app)
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.Monitor") == .monitor)
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.ShieldConfig") == .shieldConfig)
        #expect(LogSource.current(bundleIdentifier: "dev.bchen.OpenAppLock.ShieldAction") == .shieldAction)
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
        #expect(LogFilename.parse("2026-06-22.log") == nil)   // no source
        #expect(LogFilename.parse("app-not-a-date.log") == nil)
    }

    @Test("Timestamp prefix of a line equals the rendered timestamp")
    func timestampPrefix() {
        let entry = LogEntry(
            date: fixedDate, level: .debug, source: .report, category: .report, message: "x")
        #expect(LogTimestamp.prefix(ofLine: entry.line) == "2026-06-22T14:03:11.482Z")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Use the Xcode MCP `RunSomeTests` for `OpenAppLockTests/DiagnosticLogTests` (get the tab id from `XcodeListWindows`).
Expected: FAIL to compile — `LogEntry`, `LogSource`, etc. are undefined.

- [ ] **Step 3: Write the minimal implementation**

Create `Shared/LogEntry.swift`:

```swift
//
//  LogEntry.swift
//  OpenAppLock
//

import Foundation

/// Severity of a diagnostic entry. `event` flags the load-bearing
/// "a block/threshold actually fired" lines for easy grepping; it maps to the
/// unified log's `.default` (notice) level.
enum LogLevel: String, Sendable, CaseIterable {
    case debug, info, event, error
    /// Upper-cased token used in the line, e.g. `EVENT`.
    var tag: String { rawValue.uppercased() }
}

/// The area a log entry belongs to — both the `os.Logger` category (for Console
/// filtering) and the in-line `[source/category]` tag.
enum LogCategory: String, Sendable {
    case enforcer, scheduler, shield, monitor, report
    case usage, dayStart, session, appList, rule, auth, lifecycle
}

/// Which process wrote an entry, inferred from the running bundle so no
/// extension has to wire itself up.
enum LogSource: String, Sendable {
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
enum LogTimestamp {
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
        guard stem.count > 11 else { return nil }       // "x-YYYY-MM-DD" is 12+
        let day = String(stem.suffix(10))
        guard isDayKey(day) else { return nil }
        let source = String(stem.dropLast(11))           // drop "-YYYY-MM-DD"
        guard !source.isEmpty else { return nil }
        return (source, day)
    }

    /// True for a `YYYY-MM-DD` all-digit day key.
    static func isDayKey(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

/// One diagnostic record. `line` is the canonical single-line rendering written
/// to the per-process file and shown on export.
struct LogEntry: Sendable {
    let date: Date
    let level: LogLevel
    let source: LogSource
    let category: LogCategory
    let message: String

    var line: String {
        "\(LogTimestamp.string(from: date)) [\(level.tag)] "
            + "[\(source.rawValue)/\(category.rawValue)] \(Self.sanitize(message))"
    }

    /// Collapses newlines and tabs to spaces so each entry stays exactly one line.
    static func sanitize(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

`RunSomeTests` for `OpenAppLockTests/DiagnosticLogTests`. Expected: PASS (5 tests).

Note on the `entryLine` expectation: if the `ISO8601DateFormatter` rendering of `1_781_186_591.482` differs by a rounding digit on the test machine, adjust the literal to the exact emitted string (read it from the failure) — the timestamp formatter, not the test's intent, is the source of truth.

- [ ] **Step 5: Commit**

```bash
git add Shared/LogEntry.swift OpenAppLockTests/DiagnosticLogTests.swift
git commit -m "feat: diagnostic log value types and line formatting

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Merge & retention pure functions

**Files:**
- Create: `Shared/LogMerge.swift`, `Shared/LogRetention.swift`
- Test: `OpenAppLockTests/DiagnosticLogTests.swift` (extend)

**Interfaces:**
- Consumes: `LogTimestamp`, `LogFilename` (Task 1).
- Produces:
  - `enum LogMerge { static func merge(perFile: [[String]]) -> [String] }`
  - `enum LogRetention { static func filesToPrune(filenames: [String], today: Date, retentionDays: Int, calendar: Calendar) -> [String] }`

- [ ] **Step 1: Write the failing tests**

Append to `OpenAppLockTests/DiagnosticLogTests.swift`:

```swift
@MainActor
struct LogMergeRetentionTests {
    @Test("Merge interleaves files chronologically by the UTC prefix")
    func mergeChronological() {
        let app = [
            "2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1",
            "2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2",
        ]
        let monitor = [
            "2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1",
        ]
        let merged = LogMerge.merge(perFile: [app, monitor])
        #expect(merged == [
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
        #expect(merged == [
            "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-first",
            "2026-06-22T10:00:00.000Z [INFO] [app/usage] A-second",
            "2026-06-22T10:00:00.000Z [INFO] [monitor/usage] B-first",
        ])
    }

    @Test("Prune selects files strictly older than the retention window")
    func prune() {
        let today = date(2026, 6, 22)   // from TestSupport (UTC calendar)
        let names = [
            "app-2026-06-22.log",      // today — keep
            "app-2026-06-08.log",      // 14 days ago — keep (boundary)
            "monitor-2026-06-07.log",  // 15 days ago — prune
            "app-2026-05-01.log",      // old — prune
            "notes.txt",               // not a log — ignored
        ]
        let pruned = Set(
            LogRetention.filesToPrune(
                filenames: names, today: today, retentionDays: 14, calendar: utc))
        #expect(pruned == ["monitor-2026-06-07.log", "app-2026-05-01.log"])
    }
}
```

- [ ] **Step 2: Run to verify failure**

`RunSomeTests` for `OpenAppLockTests/DiagnosticLogTests`. Expected: FAIL (compile — `LogMerge`/`LogRetention` undefined).

- [ ] **Step 3: Write the implementations**

Create `Shared/LogMerge.swift`:

```swift
//
//  LogMerge.swift
//  OpenAppLock
//

import Foundation

/// Merges the per-process daily files for one day into a single chronological
/// timeline. Sorting on the 24-char UTC timestamp prefix is exact because every
/// line carries a fixed-width UTC stamp; ties keep file order then within-file
/// order, so the merge is fully deterministic and stable.
enum LogMerge {
    static func merge(perFile: [[String]]) -> [String] {
        var indexed: [(key: String, file: Int, line: Int, text: String)] = []
        for (fileIndex, lines) in perFile.enumerated() {
            for (lineIndex, text) in lines.enumerated() {
                indexed.append((LogTimestamp.prefix(ofLine: text), fileIndex, lineIndex, text))
            }
        }
        indexed.sort { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            if lhs.file != rhs.file { return lhs.file < rhs.file }
            return lhs.line < rhs.line
        }
        return indexed.map(\.text)
    }
}
```

Create `Shared/LogRetention.swift`:

```swift
//
//  LogRetention.swift
//  OpenAppLock
//

import Foundation

/// Chooses which log files have aged out. A file is pruned when its day bucket
/// is strictly older than `retentionDays` before today (so a 14-day window keeps
/// today through 14 days ago, inclusive).
enum LogRetention {
    static func filesToPrune(
        filenames: [String], today: Date, retentionDays: Int, calendar: Calendar = .current
    ) -> [String] {
        let startOfToday = calendar.startOfDay(for: today)
        guard let cutoff = calendar.date(
            byAdding: .day, value: -retentionDays, to: startOfToday) else { return [] }
        return filenames.filter { name in
            guard let parsed = LogFilename.parse(name),
                  let day = dayDate(parsed.day, calendar: calendar) else { return false }
            return day < cutoff
        }
    }

    /// Midnight (local) of a `YYYY-MM-DD` key, or nil if unparseable.
    private static func dayDate(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }
}
```

- [ ] **Step 4: Run to verify passing**

`RunSomeTests` for `OpenAppLockTests/DiagnosticLogTests`. Expected: PASS (all tests in the file).

- [ ] **Step 5: Commit**

```bash
git add Shared/LogMerge.swift Shared/LogRetention.swift OpenAppLockTests/DiagnosticLogTests.swift
git commit -m "feat: chronological log merge and age-based retention

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Per-process file writer

**Files:**
- Create: `Shared/LogFileWriter.swift`
- Test: `OpenAppLockTests/LogFileWriterTests.swift`

**Interfaces:**
- Consumes: `LogSource`, `LogFilename` (Task 1); `UsageLedger.dayKey` (existing).
- Produces:
  - `enum DiagnosticLogLocation { static func defaultDirectory() -> URL }`
  - `final class LogFileWriter: @unchecked Sendable { init(directory: URL, source: LogSource, calendar: Calendar); func append(_ line: String, day: Date) }`

- [ ] **Step 1: Write the failing test**

Create `OpenAppLockTests/LogFileWriterTests.swift`:

```swift
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
        #expect(contents == """
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

        let names = Set(
            try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(names == ["monitor-2026-06-22.log", "monitor-2026-06-23.log"])
    }

    @Test("Creates the directory if it does not exist yet")
    func createsDirectory() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let nested = parent.appendingPathComponent("Logs", isDirectory: true)
        let writer = LogFileWriter(directory: nested, source: .report, calendar: utc)
        writer.append("hello", day: date(2026, 6, 22))
        #expect(FileManager.default.fileExists(
            atPath: nested.appendingPathComponent("report-2026-06-22.log").path))
    }
}
```

- [ ] **Step 2: Run to verify failure**

`RunSomeTests` for `OpenAppLockTests/LogFileWriterTests`. Expected: FAIL (compile — `LogFileWriter` undefined).

- [ ] **Step 3: Write the implementation**

Create `Shared/LogFileWriter.swift`:

```swift
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
        let base = FileManager.default
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
```

- [ ] **Step 4: Run to verify passing**

`RunSomeTests` for `OpenAppLockTests/LogFileWriterTests`. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Shared/LogFileWriter.swift OpenAppLockTests/LogFileWriterTests.swift
git commit -m "feat: per-process serial log file writer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: The `Diag` facade (dual sink)

**Files:**
- Create: `Shared/DiagnosticLog.swift`
- Test: `OpenAppLockTests/LogFileWriterTests.swift` (extend with an end-to-end test)

**Interfaces:**
- Consumes: everything from Tasks 1 & 3.
- Produces:
  - `enum Diag { static func configure(directory: URL, source: LogSource); static func log(_ category: LogCategory, _ level: LogLevel = .info, _ message: String, file: String = #fileID, function: String = #function, line: Int = #line); static func error(_ category: LogCategory, _ message: String, file: String = #fileID, function: String = #function, line: Int = #line) }` — `log`/`error` capture the call site and pass it into `LogEntry`; the os.Logger message also gets a `[File.swift:line]` suffix.
  - `extension LogLevel { var osType: OSLogType }`

- [ ] **Step 1: Write the failing test**

Append to `OpenAppLockTests/LogFileWriterTests.swift`:

```swift
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
        // The line starts with a 24-char UTC timestamp.
        let firstLine = contents.split(separator: "\n").first.map(String.init) ?? ""
        #expect(LogTimestamp.prefix(ofLine: firstLine).hasSuffix("Z"))
    }
}
```

(Note: `Diag.configure(directory:source:)` takes an explicit `source` for tests so it does not depend on the test bundle's bundle id.)

- [ ] **Step 2: Run to verify failure**

`RunSomeTests` for `OpenAppLockTests/LogFileWriterTests`. Expected: FAIL (compile — `Diag` undefined).

- [ ] **Step 3: Write the implementation**

Create `Shared/DiagnosticLog.swift`:

```swift
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
/// `MainActor`). See `Docs/Agents/Specs/DIAGNOSTIC_LOGGING.md`.
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
    static func configure(directory: URL, source: LogSource = Diag.source) {
        lock.lock(); defer { lock.unlock() }
        writer = LogFileWriter(directory: directory, source: source)
    }

    static func log(
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

    static func error(
        _ category: LogCategory, _ message: String,
        file: String = #fileID, function: String = #function, line: Int = #line
    ) {
        log(category, .error, message, file: file, function: function, line: line)
    }

    private static func fileWriter() -> LogFileWriter {
        lock.lock(); defer { lock.unlock() }
        if let writer { return writer }
        let created = LogFileWriter(
            directory: DiagnosticLogLocation.defaultDirectory(), source: source)
        writer = created
        return created
    }

    private static func logger(for category: LogCategory) -> Logger {
        lock.lock(); defer { lock.unlock() }
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
```

- [ ] **Step 4: Run to verify passing**

`RunSomeTests` for `OpenAppLockTests/LogFileWriterTests`. Expected: PASS.

If the compiler reports `MainActor`-isolation errors on the `static` members (the app target's default isolation), confirm each `static func`/stored property is reachable from `nonisolated` context — the `nonisolated(unsafe)` on the stored vars plus the lock is the intended pattern; do not add `@MainActor`.

- [ ] **Step 5: Commit**

```bash
git add Shared/DiagnosticLog.swift OpenAppLockTests/LogFileWriterTests.swift
git commit -m "feat: Diag dual-sink logging facade (os.Logger + file)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: App-side `LogStore` (list / merge / export / clear / prune)

**Files:**
- Create: `OpenAppLock/Services/LogStore.swift`
- Test: `OpenAppLockTests/LogStoreTests.swift`

**Interfaces:**
- Consumes: `LogFilename`, `LogMerge`, `LogRetention`, `LogFileWriter`/`LogSource` (Tasks 1–3); `UsageLedger.dayKey`.
- Produces:
  - `@Observable final class LogStore { init(directory: URL, calendar: Calendar); func availableDays() -> [LogStore.Day]; func mergedText(for dayKey: String) -> String; func exportFile(for dayKey: String) throws -> URL; func clearAll(); func prune(today: Date, retentionDays: Int) }`
  - `struct LogStore.Day: Identifiable, Equatable { let key: String; let lineCount: Int; let byteCount: Int; var id: String }`

- [ ] **Step 1: Write the failing tests**

Create `OpenAppLockTests/LogStoreTests.swift`:

```swift
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
        try write("app-2026-06-22.log", [
            "2026-06-22T01:00:00.000Z [INFO] [app/rule] b",
            "2026-06-22T02:00:00.000Z [INFO] [app/rule] c",
        ], in: dir)
        try write("monitor-2026-06-22.log", ["2026-06-22T01:30:00.000Z [EVENT] [monitor/monitor] m"], in: dir)
        try write("README.txt", ["ignore me"], in: dir)

        let store = LogStore(directory: dir, calendar: utc)
        let days = store.availableDays()
        #expect(days.map(\.key) == ["2026-06-22", "2026-06-20"])
        #expect(days[0].lineCount == 3)   // 2 app + 1 monitor
        #expect(days[1].lineCount == 1)
    }

    @Test("Merged text for a day interleaves all sources chronologically")
    func mergedText() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("app-2026-06-22.log", [
            "2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1",
            "2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2",
        ], in: dir)
        try write("monitor-2026-06-22.log", [
            "2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1",
        ], in: dir)

        let store = LogStore(directory: dir, calendar: utc)
        let text = store.mergedText(for: "2026-06-22")
        #expect(text == """
        2026-06-22T10:00:00.000Z [INFO] [app/enforcer] a1
        2026-06-22T10:00:02.000Z [EVENT] [monitor/monitor] m1
        2026-06-22T10:00:05.000Z [INFO] [app/enforcer] a2
        """)
    }

    @Test("Export writes the merged text to a .txt file named for the day")
    func exportFile() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("app-2026-06-22.log", ["2026-06-22T10:00:00.000Z [INFO] [app/rule] only"], in: dir)
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
```

- [ ] **Step 2: Run to verify failure**

`RunSomeTests` for `OpenAppLockTests/LogStoreTests`. Expected: FAIL (compile — `LogStore` undefined).

- [ ] **Step 3: Write the implementation**

Create `OpenAppLock/Services/LogStore.swift`:

```swift
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
            let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: true).count
            let bytes = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let running = byDay[parsed.day] ?? (0, 0)
            byDay[parsed.day] = (running.lines + lines, running.bytes + (bytes ?? 0))
        }
        return byDay
            .map { Day(key: $0.key, lineCount: $0.value.lines, byteCount: $0.value.bytes) }
            .sorted { $0.key > $1.key }
    }

    /// All sources for `dayKey`, merged chronologically and joined by newlines.
    func mergedText(for dayKey: String) -> String {
        let perFile: [[String]] = logFilenames()
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
```

- [ ] **Step 4: Run to verify passing**

`RunSomeTests` for `OpenAppLockTests/LogStoreTests`. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Services/LogStore.swift OpenAppLockTests/LogStoreTests.swift
git commit -m "feat: LogStore for listing, merging, exporting, pruning logs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: App wiring — configure, prune, inject, seed under UI testing

**Files:**
- Modify: `OpenAppLock/Services/LaunchConfiguration.swift`
- Modify: `OpenAppLock/OpenAppLockApp.swift`
- Test: `OpenAppLockTests/LaunchSupportTests.swift`

**Interfaces:**
- Consumes: `Diag.configure`, `LogStore`, `DiagnosticLogLocation` (Tasks 4–5).
- Produces: `LaunchConfiguration.seedLogs: Bool` (+ `-seed-logs` flag); a `LogStore` placed in the SwiftUI environment; logs routed to a per-launch temp dir and seeded with deterministic entries under UI testing.

- [ ] **Step 1: Write the failing test**

Find the existing `LaunchConfiguration` parsing tests in `OpenAppLockTests/LaunchSupportTests.swift` and add:

```swift
@Test("Parses the -seed-logs flag")
func parsesSeedLogs() {
    let on = LaunchConfiguration.parse(arguments: ["-ui-testing", "-seed-logs"])
    #expect(on.seedLogs == true)
    let off = LaunchConfiguration.parse(arguments: ["-ui-testing"])
    #expect(off.seedLogs == false)
}
```

(Match the surrounding test style in that file — it may be a `struct` of `@Test`s or standalone; mirror whatever is there.)

- [ ] **Step 2: Run to verify failure**

`RunSomeTests` for `OpenAppLockTests/LaunchSupportTests`. Expected: FAIL (`seedLogs` undefined).

- [ ] **Step 3a: Add the launch flag**

In `OpenAppLock/Services/LaunchConfiguration.swift`, add the field (near `notificationsAuthorized`):

```swift
    /// Seeds a few deterministic diagnostic-log entries at launch (UI tests),
    /// so the Settings → Logs export flow has known content to assert against.
    var seedLogs = false
```

Add the flag constant (near `notificationsAuthorizedFlag`):

```swift
    static let seedLogsFlag = "-seed-logs"
```

And in `parse(arguments:)` (near the `notificationsAuthorized` line):

```swift
        config.seedLogs = arguments.contains(seedLogsFlag)
```

- [ ] **Step 3b: Wire the app**

In `OpenAppLock/OpenAppLockApp.swift`, add a `LogStore` stored property and `@State`:

```swift
    @State private var logStore: LogStore
```

At the **top of `init()`** (right after `let config = LaunchConfiguration.current`), configure logging before anything else can log:

```swift
        // Diagnostic logging: app-group `Logs/` in production; a wiped per-launch
        // temp dir under UI testing so the export flow is hermetic.
        let logsDirectory: URL
        if config.isUITesting {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("DiagLogsUITest", isDirectory: true)
            try? FileManager.default.removeItem(at: temp)
            logsDirectory = temp
        } else {
            logsDirectory = DiagnosticLogLocation.defaultDirectory()
        }
        Diag.configure(directory: logsDirectory)
        let logStore = LogStore(directory: logsDirectory)
        if !config.isUITesting {
            logStore.prune()
        }
        _logStore = State(initialValue: logStore)
        Diag.log(.lifecycle, "app launch (uiTesting=\(config.isUITesting))")
        if config.seedLogs {
            Diag.log(.rule, .info, "SEED-MARKER seeded rule snapshot")
            Diag.log(.enforcer, .event, "SEED-MARKER refresh applied a shield")
            Diag.log(.monitor, .error, "SEED-MARKER simulated threshold drop")
        }
```

Inject it into the environment in `body`:

```swift
            RootView()
                .environment(authorization)
                .environment(notificationAuthorization)
                .environment(enforcer)
                .environment(settings)
                .environment(logStore)
```

- [ ] **Step 4: Run to verify passing & build**

`RunSomeTests` for `OpenAppLockTests/LaunchSupportTests` → PASS. Then `BuildProject` (app scheme) → build succeeds. If `Diag.configure` source-defaulting fails to resolve, pass the source explicitly is unnecessary here — the app's bundle id infers `.app`.

- [ ] **Step 5: Commit**

```bash
git add OpenAppLock/Services/LaunchConfiguration.swift OpenAppLock/OpenAppLockApp.swift OpenAppLockTests/LaunchSupportTests.swift
git commit -m "feat: configure logging at launch, inject LogStore, seed under UI testing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Settings UI — Diagnostics section, day list, detail, export, clear

**Files:**
- Create: `OpenAppLock/Views/Settings/DiagnosticLogsView.swift`
- Modify: `OpenAppLock/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `@Environment(LogStore.self)` (Task 6).
- Produces: `DiagnosticLogsView`, `LogDayDetailView`; a Settings row with id `diagnosticsLogsRow`. Day rows: `logDayRow-<key>`; export control: `exportLogButton`; clear: `clearLogsButton`.

- [ ] **Step 1: Add the view**

Create `OpenAppLock/Views/Settings/DiagnosticLogsView.swift`:

```swift
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
                    Text("Each day merges the app and all Screen Time extensions, oldest entries first. Logs older than 14 days are removed automatically.")
                }
                Section {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Text("Clear All Logs")
                    }
                    .accessibilityIdentifier("clearLogsButton")
                }
            }
        }
        .navigationTitle("Logs")
        .onAppear { days = logStore.availableDays() }
        .confirmationDialog(
            "Clear all logs?", isPresented: $showClearConfirmation, titleVisibility: .visible
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
```

- [ ] **Step 2: Add the Settings row**

In `OpenAppLock/Views/Settings/SettingsView.swift`, after the Notifications `Section` (around line 90) and before `linkSection`, insert:

```swift
                Section {
                    NavigationLink {
                        DiagnosticLogsView()
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    .accessibilityIdentifier("diagnosticsLogsRow")
                } header: {
                    Text("Diagnostics").textCase(nil)
                } footer: {
                    Text("Records how and when blocks execute, for troubleshooting. Export a day to share it.")
                }
```

- [ ] **Step 3: Build & visually verify**

`BuildProject` (app scheme) → succeeds. Then verify the screen renders: use the Xcode MCP `RenderPreview` on a `#Preview` of `DiagnosticLogsView` if one is added, or build-and-run on a simulator and navigate Settings → Diagnostics → Logs. Per project policy, if the simulator/Xcode MCP is unavailable, say so and hand UI verification back to the maintainer.

Optionally add a `#Preview` at the bottom of `DiagnosticLogsView.swift` that injects a `LogStore` pointed at a temp dir with a couple of seeded files, to enable `RenderPreview`.

- [ ] **Step 4: Commit**

```bash
git add OpenAppLock/Views/Settings/DiagnosticLogsView.swift OpenAppLock/Views/Settings/SettingsView.swift
git commit -m "feat: Settings Diagnostics → Logs list, detail, export, clear

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Instrument the enforcement + state-change layer

Add `Diag.log(...)` calls at the sites below. **Additive only** — change no control flow, no return values, no signatures. After wiring, the entire existing unit + UI suite must still pass unchanged.

**Verbosity bar:** reading a day's log back must let you tell *exactly* what happened, spot anomalies, and trace each to code (the trailing `[File.swift:line function]` gives the anchor). At each site log the **inputs**, the **decision**, and the **outcome** — and crucially the **"why-not" branches**, which is where blocking bugs hide:
- In `RuleEnforcer.refresh`: log each rule's id/kind/status and *why* it was or wasn't shielded (disabled / paused-until / not-scheduled-today / budget spent vs. remaining / inside a granted open session / open-limit gate), and the **before→after** shielded set (which ids gained or lost a shield this pass) plus `appRemovalDenied` transitions.
- In the monitor: log accepted *and* **rejected** events — a stale threshold drop logs the event value and the bound it failed (`minutesSinceMidnight`, confirmed day-start), not silence.
- In `UsageLedger`/report: log the prior value, the incoming value, and the stored result (so a counter that "stalls at 14/15" is visible as the exact sequence of writes).
- At save sites: log what changed and whether a re-enforce ran.

Keep each message one line and information-dense; prefer `rule-<first8>` id prefixes and concrete numbers over prose.

**Files (modify):**
- `OpenAppLock/Services/RuleEnforcer.swift`
- `Shared/ShieldController.swift` (real `ManagedSettingsShieldController` only — never the mock)
- `OpenAppLock/Services/RuleScheduler.swift`
- `OpenAppLockMonitor/DeviceActivityMonitorExtension.swift`
- `Shared/LimitEnforcement.swift`
- `Shared/UsageLedger.swift` (real `UsageLedger` write methods only — never `MockUsageLedger`)
- `OpenAppLockReport/RuleUsageReportWriter.swift`
- `Shared/DayStartStore.swift`
- `Shared/OpenSessionStore.swift` and `OpenAppLockShieldAction/ShieldActionExtension.swift`
- The app-list save path and rule save path (find with the searches in Step 1)

- [ ] **Step 1: Locate the save paths**

```bash
cd /Users/bchendev/Developer/OpenAppLock
grep -rn "modelContext.save\|context.save\|\.save()" OpenAppLock/Views/AppLists OpenAppLock/Views/Rules
grep -rln "AppList" OpenAppLock/Views/AppLists
```

Note the file + function where an `AppList`'s `selectionData` is persisted (the "app list save" bug site) and where a `BlockingRule` is created/edited and saved.

- [ ] **Step 2: Add the calls**

Representative examples — replicate the pattern at each site, keeping messages short and including identifiers/counts that explain *why* a block did or didn't happen:

`RuleEnforcer.refresh(...)` — at the start, per apply, and at the end:

```swift
    func refresh(rules: [BlockingRule], at now: Date = .now, calendar: Calendar = .current) {
        Diag.log(.enforcer, "refresh: \(rules.count) rules at \(LogTimestamp.string(from: now))")
        var blocking: Set<UUID> = []
        var shielded: Set<UUID> = []
        for rule in rules {
            // ...existing pause-expiry and day-start code...
            let usage = usage(for: rule, at: now, calendar: calendar)
            let isBlocking = rule.status(at: now, calendar: calendar, usage: usage).isActive
            if isBlocking { blocking.insert(rule.id) }
            guard isBlocking || shouldGateOpenLimit(rule, at: now, calendar: calendar) else {
                continue
            }
            shielded.insert(rule.id)
            Diag.log(.enforcer, .event,
                "shield rule-\(rule.id.uuidString.prefix(8)) \(rule.kind.rawValue) "
                    + "blocking=\(isBlocking) usedMin=\(usage?.minutesUsed ?? -1)")
            shields.applyShield(/* ...unchanged... */)
        }
        shields.clearShields(except: shielded)
        blockingRuleIDs = blocking
        Diag.log(.enforcer, "refresh done: blocking=\(blocking.count) shielded=\(shielded.count)")
        // ...existing setAppRemovalDenied / scheduler?.sync / notification sync...
    }
```

`ManagedSettingsShieldController` — at the end of `applyShield`, in `clearShield`, and in `setAppRemovalDenied`:

```swift
        Diag.log(.shield, .event,
            "apply rule-\(ruleID.uuidString.prefix(8)) mode=\(mode) adult=\(blockAdultContent)")
```
```swift
    func clearShield(ruleID: UUID) {
        Diag.log(.shield, .event, "clear rule-\(ruleID.uuidString.prefix(8))")
        store(for: ruleID).clearAllSettings()
        untrack(ruleID: ruleID)
    }
```
```swift
        Diag.log(.shield, "appRemovalDenied=\(denied)")
```

Monitor extension callbacks (`intervalDidStart` / `intervalDidEnd` / `eventDidReachThreshold` / midnight reset / day-start confirm) — log the activity/event name on entry, e.g.:

```swift
        Diag.log(.monitor, .event, "eventDidReachThreshold \(event.rawValue) activity=\(activity.rawValue)")
```

`UsageLedger` write methods — log new totals (real store only):

```swift
    func recordMinutesUsed(_ minutes: Int, for ruleID: UUID, onDayContaining date: Date, calendar: Calendar = .current) {
        var usage = self.usage(for: ruleID, onDayContaining: date, calendar: calendar)
        usage.minutesUsed = max(usage.minutesUsed, minutes)
        setUsage(usage, for: ruleID, onDayContaining: date, calendar: calendar)
        Diag.log(.usage, .event,
            "minutes rule-\(ruleID.uuidString.prefix(8)) -> \(usage.minutesUsed) (event=\(minutes))")
    }
```
Add equivalents in `recordAuthoritativeMinutes` (`.report` category) and `recordOpen` (`.session`).

Report writer, `DayStartStore.setConfirmedStart`, `OpenSessionStore` session start/expiry, and the shield-action open press — one `Diag.log(.report/.dayStart/.session, .event, "…")` each, naming the rule id prefix and the new value.

App-list save site:

```swift
        Diag.log(.appList, .event,
            "saved list \"\(list.name)\" selectionCount=\(AppSelectionCodec.count(of: selection))")
```
Rule save site:

```swift
        Diag.log(.rule, .event, "saved rule \"\(rule.name)\" kind=\(rule.kind.rawValue) enabled=\(rule.isEnabled)")
```

- [ ] **Step 3: Build every target**

`BuildProject` for the app scheme (compiles the app + embeds all four extensions). Confirm `Shared/` logging compiles in the extension targets too (no `MainActor` hop, no missing symbol). Expected: build succeeds.

- [ ] **Step 4: Run the full unit suite — behavior unchanged**

`RunAllTests`. Expected: PASS, with no regressions versus the pre-instrumentation run (logging is additive; mocks were not instrumented, so assertion counts are unchanged).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: instrument enforcement and state-change paths with Diag logs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: UI test — the export flow

**Files:**
- Create: `OpenAppLockUITests/DiagnosticLogsUITests.swift`

**Interfaces:**
- Consumes: `-seed-logs` (Task 6); ids `diagnosticsLogsRow`, `logDayRow-<key>`, `logDayText`, `exportLogButton`, `clearLogsButton`, `noLogsLabel`; helpers `launchOpenAppLock`, `goToSettingsTab`, `element(_:)`, `waitToAppear()`.

- [ ] **Step 1: Write the test**

Create `OpenAppLockUITests/DiagnosticLogsUITests.swift`:

```swift
//
//  DiagnosticLogsUITests.swift
//  OpenAppLockUITests
//

import XCTest

final class DiagnosticLogsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Today's local day key, matching `UsageLedger.dayKey` / the file bucket.
    private var todayKey: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func testSeededLogsExportAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-onboarding-completed", "-seed-logs"]
        app.launch()

        app.goToSettingsTab()

        // Settings → Diagnostics → Logs
        let logsRow = app.element("diagnosticsLogsRow")
        XCTAssertTrue(logsRow.waitForExistence(timeout: 5))
        logsRow.tap()

        // Today's seeded day row is present; open it.
        let dayRow = app.element("logDayRow-\(todayKey)")
        XCTAssertTrue(dayRow.waitForExistence(timeout: 5), "expected a log day row for today")
        dayRow.tap()

        // The merged day text contains a seeded marker and the export control exists.
        let dayText = app.element("logDayText")
        XCTAssertTrue(dayText.waitForExistence(timeout: 5))
        XCTAssertTrue(dayText.label.contains("SEED-MARKER"), "seeded entries should appear in the day log")
        XCTAssertTrue(app.element("exportLogButton").waitForExistence(timeout: 5))

        // Back to the days list, clear, confirm, and expect the empty state.
        app.navigationBars[todayKey].buttons.firstMatch.tap()  // back to "Logs"
        let clear = app.element("clearLogsButton")
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        // Confirmation dialog's destructive action (sheet button).
        app.sheets.buttons["Clear All Logs"].tap()

        XCTAssertTrue(app.element("noLogsLabel").waitForExistence(timeout: 5),
                      "after clearing, the empty state should show")
    }
}
```

Notes:
- The confirmation action is queried via `app.sheets.buttons[...]` (per the AGENTS gotcha about `confirmationDialog`); the **Cancel** button is intentionally not asserted.
- Back navigation uses the nav bar's first button so it works on both iPhone and iPad form sheets (per the iPad gotchas).
- The app also writes its own real entries during launch; the assertions key off the unique `SEED-MARKER` text and the empty-state-after-clear, which hold within the test window (the 30 s enforcer loop does not re-fire while Settings is open).

- [ ] **Step 2: Run the UI test**

`RunSomeTests` for `OpenAppLockUITests/DiagnosticLogsUITests`. Pick an **iPhone simulator** destination first; expected: PASS. If a row tap is dropped, the helpers already retry; re-run once before investigating.

- [ ] **Step 3: Run on the iPad destination too (CI matrix parity)**

If the CI matrix runs iPad, run the same test on an iPad simulator. Expected: PASS (navigation uses idiom-agnostic helpers).

- [ ] **Step 4: Commit**

```bash
git add OpenAppLockUITests/DiagnosticLogsUITests.swift
git commit -m "test: UI flow for diagnostic log export and clear

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Docs, full verification, PR

**Files:**
- Modify: `AGENTS.md` (Rules feature map + a known-gaps note)
- Verify: full build + test + manual UI validation

- [ ] **Step 1: Update AGENTS.md**

In the **Repo layout** `Shared/` description, add the logging files. In the **Rules feature map** table, add a row:

```
| Diagnostic logging + daily export | `Shared/DiagnosticLog.swift`, `Shared/LogFileWriter.swift`, `OpenAppLock/Services/LogStore.swift`, `OpenAppLock/Views/Settings/DiagnosticLogsView.swift` |
```

In the **UI-test harness** argument table, add:

```
| `-seed-logs` | Seeds deterministic diagnostic-log entries for the export flow |
```

Add a short **Known gaps / next steps** bullet noting that on-device, the diagnostic logs are the primary instrument for verifying time-limit blocking behavior, and that instrumentation breadth may widen after the first round of device logs.

- [ ] **Step 2: Full suite**

`RunAllTests` (iPhone). Expected: PASS. Then build the app scheme once more to confirm all extensions embed cleanly.

- [ ] **Step 3: Manual UI validation**

Build-and-run on a simulator without `-ui-testing` (real `LogStore` against the app group): open Settings → Diagnostics → Logs, confirm a day appears after using the app briefly, open it, confirm entries render and the share button presents a sheet, then Clear and confirm the empty state. If Xcode MCP / a simulator is unavailable, state so explicitly and hand this step to the maintainer (per project policy).

- [ ] **Step 4: Commit docs**

```bash
git add AGENTS.md
git commit -m "docs: index diagnostic logging in the feature map and harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feat/diagnostic-logging
gh pr create --title "feat: diagnostic logging system with per-day export" --body "<summary + test plan; note it stacks on feat/notifications (#22) and must merge after it; include the Generated-with-Claude-Code footer>"
```

The PR base is `main`, but the branch contains `feat/notifications` (#22) commits — call this out in the PR body so the reviewer merges #22 first (or rebases). End the PR body with the "Generated with Claude Code" footer.

---

## Self-Review (completed)

- **Spec coverage:** dual sink (Tasks 1,3,4) · per-process daily files + source inference (Tasks 1,3) · line format/levels/categories (Task 1) · merge + day list + export + clear + 14-day prune (Tasks 2,5) · always-on, no toggle (Tasks 4,6 — `configure` + always-call `log`; Settings has only Export/Clear, Task 7) · Settings UI + ids (Task 7) · instrumentation list (Task 8) · unit + UI testing incl. `-seed-logs` temp-dir routing (Tasks 1–6, 9) · docs (Task 10). No gaps.
- **Placeholder scan:** none — every code step is concrete.
- **Type consistency:** `Diag.log(_:_:_:)` / `Diag.configure(directory:source:)`, `LogStore.availableDays()/mergedText(for:)/exportFile(for:)/clearAll()/prune(today:retentionDays:)`, `LogStore.Day.{key,lineCount,byteCount}`, `LogFilename.make/parse`, `LogMerge.merge(perFile:)`, `LogRetention.filesToPrune(filenames:today:retentionDays:calendar:)`, `LogTimestamp.prefix(ofLine:)/prefixLength`, `LogSource.current(bundleIdentifier:)` are used identically across tasks. `UsageLedger.dayKey` reused for day buckets.
- **Known risk:** the Task 1 timestamp literal depends on the platform `ISO8601DateFormatter`; Step 4 of Task 1 says to reconcile the literal to the emitted string if a fractional digit differs.
