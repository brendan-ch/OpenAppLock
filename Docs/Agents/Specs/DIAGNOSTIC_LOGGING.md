# Diagnostic Logging & Daily Export

Design spec for a consistent, cross-process logging system whose persisted
output can be exported from Settings as a per-day text file. Agent-managed
(lives under `Docs/Agents/`). The behavior source of truth is the doc comments
on the owning source files (indexed by the "Rules feature map" in `AGENTS.md`);
this spec is the design rationale behind those changes.

## 1. Problem & purpose

Time-limit blocking has always been inconsistent, and other bugs exist (e.g.
app-list edits not registering after a save). The Screen Time APIs
(`DeviceActivity` thresholds, monitor/shield/report extensions) deliver their
work across **five separate processes** — the app plus four extensions — at
times iOS chooses, so the real on-device behavior is largely invisible from any
single vantage point. There is currently **no logging** in the codebase (one
stray `print()` in `RuleScheduler`).

Goal: capture *how and when blocks execute* (and the surrounding state changes)
durably enough that a day's worth of logs, handed off, is sufficient to
determine the real behavior of the Screen Time API and correct the app to match.

Requirements (confirmed):

- Live-viewable in Xcode/Console while running on the simulator or a device.
- Exportable from **Settings** as a text file for a **given day**.
- **Always on** in every build (the target bugs only surface on-device and are
  intermittent — nothing should be missed). Settings exposes Export + Clear only,
  no enable/disable toggle.
- **14-day** on-device retention, auto-pruned.
- Instrument the **enforcement + state-change layer** (not pure UI lifecycle).

> Scope note: this is the initial instrumentation footprint. Depending on how
> well these logs help with debugging, the set of instrumented call sites may be
> widened (e.g. to UI lifecycle) in later work.

## 2. Why a persisted file, not just `os.Logger`

`os.Logger` (unified logging) is perfect for **live** viewing — Xcode console
and Console.app, filterable by subsystem/category — but on iOS `OSLogStore` can
only read back the **current process's** entries. The app therefore cannot
harvest the four extensions' unified-log entries for export. A shared persisted
store in the app group is the only way to assemble one merged timeline across
all five processes. The system is therefore a **dual sink**: every log call
writes to `os.Logger` (live) *and* appends to a file (durable/exportable).

## 3. The persisted store — per-process daily files

Files live in the existing app group container
(`group.dev.bchen.OpenAppLock`) under `Logs/`:

```
<appgroup>/Logs/<source>-<YYYY-MM-DD>.log
```

e.g. `app-2026-06-22.log`, `monitor-2026-06-22.log`, `report-2026-06-22.log`,
`shieldaction-2026-06-22.log`, `shieldconfig-2026-06-22.log`.

- **Per-process files, not one shared file.** Five processes appending to a
  single file would interleave and corrupt writes — iOS provides no cross-process
  file write coordination by default. Separate per-process files eliminate
  cross-process contention entirely; the merge into one timeline happens only at
  export time, by timestamp.
- **Source is auto-inferred** from `Bundle.main.bundleIdentifier`:

  | Bundle identifier | Source |
  |---|---|
  | `dev.bchen.OpenAppLock` | `app` |
  | `dev.bchen.OpenAppLock.Monitor` | `monitor` |
  | `dev.bchen.OpenAppLock.ShieldConfig` | `shieldconfig` |
  | `dev.bchen.OpenAppLock.ShieldAction` | `shieldaction` |
  | `dev.bchen.OpenAppLock.Report` | `report` |

  Anything else falls back to the last dot-component lowercased (or `app`). No
  per-extension wiring to forget.
- Each process **serializes its own writes** on a private serial queue and
  appends via open → seek-to-end → write → close, so an abruptly-terminated
  extension never loses its last lines. Volume is low (event-driven; the app's
  heaviest source is the 30 s `RuleEnforcer` loop), so open/close per entry is
  acceptable and bulletproof.

### Line format

One entry = one line. A fixed-width UTC ISO8601(ms) prefix makes a plain lexical
sort identical to chronological order, which is what the merge relies on. Every
entry also carries the **source location** it was emitted from (captured
automatically via `#fileID`/`#line`/`#function`), so a line read back from an
exported log traces straight to the code that produced it:

```
2026-06-22T14:03:11.482Z [EVENT] [app/enforcer] applied shield rule-ABC (strictest) [RuleEnforcer.swift:104 refresh(rules:at:calendar:)]
```

Fields: `<iso8601-utc-ms>` · `[<LEVEL>]` · `[<source>/<category>]` · `<message>` ·
`[<File.swift>:<line> <function>]`. Newlines and tabs are stripped from the
message (and function) so each entry stays on one line.

### Verbosity & traceability

The logs must be detailed enough that, reading a day back, one can tell *exactly*
what happened, spot anomalies, and trace each to code. Concretely, the
enforcement sites log the **inputs**, the **decision**, and the **outcome** —
including the "why-not" branches that are the usual source of blocking bugs:

- a rule that was *considered but not shielded*, and why (disabled, paused,
  not scheduled today, budget not yet spent, inside a granted open session);
- a threshold/usage event *rejected as stale* (with the value and the bound it
  failed), not just the accepted ones;
- before→after shield state on every `refresh` (which rule ids gained/lost a
  shield), so an unexpected clear or a missed apply is visible;
- an app-list or rule **save** and whether it triggered a re-enforce — the
  direct probe for "edits don't register after I save them".

- **Levels**: `debug · info · event · error`. `event` flags the load-bearing
  "a block actually executed / a threshold fired" lines for easy grepping; it
  maps to `os.Logger`'s `notice`.
- **Categories** (the `os.Logger` category and the in-line tag): `enforcer`,
  `scheduler`, `shield`, `monitor`, `report`, `usage`, `dayStart`, `session`,
  `appList`, `rule`, `auth`, `lifecycle`.

## 4. Export, retention, clear (app side — `LogStore`)

A `LogStore` in the app target owns read/merge/prune/export. All operations are
**pure and injectable** — `LogStore` and the writer take a base directory URL
and a `now` clock — so the merge/sort/prune/format logic is fully unit-testable
in a temp directory, with no app group and no device.

- **List days**: scan `Logs/`, parse the date out of each filename, dedupe
  across sources, sort newest-first. Each day carries a line count / byte size
  for display.
- **Merge a day**: read every `*-<day>.log`, split into lines, **stable-sort by
  the 24-char ISO prefix**, join → one text blob.
- **Export**: write the blob to a temp `OpenAppLock-logs-<day>.txt` and hand the
  URL to a SwiftUI `ShareLink` (Files / AirDrop / Mail).
- **Clear**: delete everything under `Logs/`.
- **Prune**: on app launch, delete files whose day is older than **14 days**
  (`filesToPrune(filenames:today:retentionDays:)`, a pure function).

## 5. Logging facade — `Diag`

A terse, thread-safe, **non-isolated** facade in `Shared/` callable from any
process/queue (extension callbacks run on arbitrary threads; the app target
defaults to `MainActor` isolation, so the logging types are explicitly
`Sendable` / non-isolated and must not hop to `MainActor`):

```swift
Diag.log(.enforcer, "refresh: applied shield rule-\(id) (strictest)")
Diag.log(.monitor, .event, "threshold minutes-15 fired for rule-\(id)")
Diag.error(.report, "authoritative write failed: \(reason)")
```

Backed by a process-wide singleton `LogFileWriter` (serial queue) plus an
`os.Logger` per category. String interpolations are emitted `.public` to the
unified log (the messages contain no secrets — Screen Time selections are
opaque tokens; rule names are the user's own and they are exporting their own
logs).

## 6. Settings UI

A new **Diagnostics** section in `SettingsView` with a row that pushes
`DiagnosticLogsView`:

- A list of available days (newest first) with a line-count/size subtitle; an
  empty state when there are no logs.
- Tap a day → a detail screen showing that day's merged log (scrollable,
  monospaced) with a **ShareLink** in the toolbar exporting the `.txt`.
- A **Clear All Logs** button (confirmation dialog) at the bottom.
- Accessibility identifiers (kept stable for UI tests): `diagnosticsLogsRow`,
  `logDayRow-<date>`, `exportLogButton`, `clearLogsButton`.

## 7. Instrumented call sites (enforcement + state-change layer)

| Area | What is logged |
|---|---|
| `RuleEnforcer.refresh` | active-rule count; each shield apply/clear with rule id + strictest-wins reason; resulting state |
| `ShieldController` apply/clear (Shared) | every shield store change (covers app **and** extension callers) |
| `RuleScheduler` | DeviceActivity activity/event registrations (`sched-…`, `minutes-…`) |
| Monitor extension | `intervalDidStart/End`, `eventDidReachThreshold` (name), midnight reset, day-start confirm |
| `LimitEnforcement` | usage-minute / open reactions and block decisions, incl. stale-event drops |
| `UsageLedger` writes | `recordMinutesUsed` / `recordAuthoritativeMinutes` / `recordOpen` with the new totals |
| Report extension | authoritative daily-total writes (per rule) |
| `DayStartStore` | confirmed daily-activity starts |
| `OpenSessionStore` / ShieldAction | open spent, session start/expiry |
| App-list save + rule save | what changed and whether a `RuleEnforcer.refresh` was triggered — targets the "app-list save doesn't register" bug |

Logging is strictly additive and must not change behavior. Where a logged file
owns feature behavior, its doc comment stays the source of truth; the new
diagnostics files carry this feature's doc comments.

## 7a. Time-limit edge cases the logs make observable

Time-limit enforcement spans five processes and most events happen with the app
closed, so the durable per-process files (not just `os.Logger`) are the field
evidence. The instrumentation is sized so each suspected bug has a log signature:

| Edge case | Log evidence |
|---|---|
| Stale cross-midnight checkpoint | `usage` `drop … (stale … minutes>sinceMidnight)` / `(no confirmed day-start)` |
| Premature / 0-usage threshold fire (iOS 26) | monitor `eventDidReachThreshold` + `usage usageEvent … sinceMidnight=` accepted, cross-checked against `report authoritative … minutes≈0` for the same rule/day |
| Missed midnight reset | **absence** of `monitor intervalDidStart` / `dayStart` near local 00:00, then a new-day `enforcer … clear` |
| Authoritative lifts a real block | `usage timeLimit … source=authoritative` + `usage WARN … authoritative lifted a real block (EC4)`; root cause `report WARN … category/web tokens NOT summed` |
| Freshness window (120 s) | `usage timeLimit … auth=…@<age>s … source=authoritative\|threshold` across consecutive refreshes |
| Same-day re-fire zeroing usage | `dayStart confirm … (zeroed today's ledger)` vs `… skipped (same-day re-fire)` |
| Monitoring restart resets counting | `scheduler dailyActivity restart … fp <old>-><new> (resets threshold accounting)` |
| `startMonitoring` threw (no enforcement) | `scheduler [ERROR] start failed …` |
| App-closed blind spot | extension entries persisted to the app-group files, exported later |
| Foreground coverage gaps | `lifecycle refresh trigger: foreground 30s loop / rule-change / scenePhase active` |

WARN-class anomalies are emitted at `error` level so they grep as `[ERROR]`.
Selection contents are never logged — only token **counts** (apps/categories/web).

## 8. Testing

TDD, with the **export path** as the priority. The bulk of coverage is unit
tests of pure logic; the UI test confirms reachability.

- **Unit**: line formatting with a fixed clock; newline/tab sanitization;
  merge + stable-sort across sources and out-of-order input; day listing +
  dedup; prune-by-age; writer round-trip in a temp dir (append, read back,
  in-process ordering); bundle-suffix → source inference.
- **UI**: under `-ui-testing` the log base dir routes to a per-launch **temp
  dir**; a new `-seed-logs` launch argument writes deterministic entries. The
  test navigates Settings → Diagnostics → Logs, asserts the seeded day row and
  its detail content, and that **Clear** empties the list. The system share
  sheet is out-of-process, so the test asserts the export control exists and is
  tappable but does not assert the sheet's contents.

## 9. File layout

```
Shared/DiagnosticLog.swift            Diag facade, LogLevel, LogCategory,
                                      LogSource inference, LogEntry formatting
Shared/LogFileWriter.swift            per-process serial append writer (injectable dir)
OpenAppLock/Services/LogStore.swift   app-side read / merge / prune / export
OpenAppLock/Views/Settings/DiagnosticLogsView.swift
                                      days list + day detail + export + clear
```

Tests added under `OpenAppLockTests/` (unit) and `OpenAppLockUITests/` (flow).
