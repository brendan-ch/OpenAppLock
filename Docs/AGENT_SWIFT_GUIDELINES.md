# Swift Guidelines

Swift coding, testing, patterns, and security standards for OpenAppLock.
Agents working on this project must follow these. They are the project-local
copy of the team's Swift standards, consolidated here so the repo is
self-contained (no dependency on any individual contributor's global config).

Where a rule meets a project specific, a **Project note** calls it out.
General/cross-language principles (immutability, small files, comprehensive
error handling, input validation) still apply on top of the Swift specifics
below.

---

## 1. Coding style

### Formatting

- **SwiftFormat** for auto-formatting, **SwiftLint** for style enforcement.
- `swift-format` is bundled with Xcode 16+ as an alternative.

### Immutability

- Prefer `let` over `var` — define everything as `let` and only change to `var`
  if the compiler requires it.
- Use `struct` with value semantics by default; use `class` only when identity
  or reference semantics are needed.
  - **Project note:** SwiftData `@Model` types are necessarily reference types
    (`BlockingRule`, `AppList`); everything in `Shared/` and `Logic/` that can
    be a value type (`RuleDraft`, `RuleSchedule`, `UsageLedger`, snapshots,
    enums like `RuleKind`/`Weekday`) is.

### Naming

Follow the [Apple API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/):

- Clarity at the point of use — omit needless words.
- Name methods and properties for their roles, not their types.
- Use `static let` for constants over global constants.

### Error handling

Use typed throws (Swift 6+) and pattern matching:

```swift
func load(id: String) throws(LoadError) -> Item {
    guard let data = try? read(from: path) else {
        throw .fileNotFound(id)
    }
    return try decode(data)
}
```

### Concurrency

Enable Swift 6 strict concurrency checking. Prefer:

- `Sendable` value types for data crossing isolation boundaries.
- Actors for shared mutable state.
- Structured concurrency (`async let`, `TaskGroup`) over unstructured `Task {}`.

> **Project note:** the app target defaults to `@MainActor` isolation, and the
> test suites are `@MainActor`. Data shared with the DeviceActivity / shield
> extensions through the app group (`RuleSnapshot`, `UsageLedger`, the
> `MonitoringPlan` naming) must remain `Sendable`.

---

## 2. Testing

### Framework

Use **Swift Testing** (`import Testing`) for new tests — `@Test` and `#expect`:

```swift
@Test("User creation validates email")
func userCreationValidatesEmail() throws {
    #expect(throws: ValidationError.invalidEmail) {
        try User(email: "not-an-email")
    }
}
```

### Test isolation

Each test gets a fresh instance — set up in `init`, tear down in `deinit`. No
shared mutable state between tests.

> **Project note:** SwiftData is the exception. Repeatedly creating
> `ModelContainer`s for this schema traps intermittently, so unit tests share
> **one** container per process and get a fresh context + data wipe per test via
> `makeInMemoryContext()` (TestSupport.swift). See AGENTS.md → "Gotchas learned
> the hard way."

### Parameterized tests

```swift
@Test("Validates formats", arguments: ["json", "xml", "csv"])
func validatesFormat(format: String) throws {
    let parser = try Parser(format: format)
    #expect(parser.isValid)
}
```

### Coverage

Target **80%+** coverage (unit + integration + critical-flow E2E).

```bash
swift test --enable-code-coverage
```

> **Project note:** this is an **Xcode project, not a SwiftPM package** — build
> and run tests through the **Xcode MCP** tools (`BuildProject`, `RunAllTests`,
> `RunSomeTests`), not `swift test` or raw `xcodebuild`. The scheme destination
> must be an iOS **simulator** or runs hang. UI flows are XCUITest
> (`OpenAppLockUITests`) driven by the launch-argument harness in AGENTS.md.

### Workflow

Red-green TDD: update `Docs/AGENT_RULES_FEATURE_SPEC.md` first for behavior changes,
write the failing test, run it (a compile failure counts as red), implement,
re-run focused tests, then the full suite. Run tests often and fail fast.

---

## 3. Patterns

### Protocol-oriented design

Define small, focused protocols. Use protocol extensions for shared defaults:

```swift
protocol Repository: Sendable {
    associatedtype Item: Identifiable & Sendable
    func find(by id: Item.ID) async throws -> Item?
    func save(_ item: Item) async throws
}
```

> **Project note:** this is how `ScreenTimeAuthorization` is structured — a
> protocol with a real FamilyControls implementation and a mock, so `Logic/`
> stays pure and unit-testable.

### Value types

- Use structs for data transfer objects and models.
- Use enums with associated values to model distinct states:

```swift
enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(Error)
}
```

> **Project note:** `RuleStatus` (`disabled / dormant / active(until:) /
> paused(until:) / upcoming(startsAt:)`) is exactly this pattern — status is
> always *derived*, never stored.

### Actor pattern

Use actors for shared mutable state instead of locks or dispatch queues:

```swift
actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: Value] = [:]

    func get(_ key: Key) -> Value? { storage[key] }
    func set(_ key: Key, value: Value) { storage[key] = value }
}
```

### Dependency injection

Inject protocols with default parameters — production uses defaults, tests
inject mocks:

```swift
struct UserService {
    private let repository: any UserRepository

    init(repository: any UserRepository = DefaultUserRepository()) {
        self.repository = repository
    }
}
```

---

## 4. Security

### Secret management

- Use **Keychain Services** for sensitive data (tokens, passwords, keys) — never
  `UserDefaults`.
- Use environment variables or `.xcconfig` files for build-time secrets.
- Never hardcode secrets in source — decompilation tools extract them trivially.

```swift
let apiKey = ProcessInfo.processInfo.environment["API_KEY"]
guard let apiKey, !apiKey.isEmpty else {
    fatalError("API_KEY not configured")
}
```

> **Project note:** OpenAppLock has no network backend or API keys today.
> `UserDefaults` (and the app-group container) is used only for non-sensitive
> rule mirroring / stray-shield cleanup — keep it that way; do not put secrets
> there.

### Transport security

- App Transport Security (ATS) is enforced by default — do not disable it.
- Use certificate pinning for critical endpoints.
- Validate all server certificates.

### Input validation

- Sanitize all user input before display to prevent injection.
- Use `URL(string:)` with validation rather than force-unwrapping.
- Validate data from external sources (APIs, deep links, pasteboard) before
  processing.

---

## 5. Tooling hooks (optional, local)

Contributors may configure PostToolUse hooks in their own
`~/.claude/settings.json` to run after editing `.swift` files:

- **SwiftFormat** — auto-format.
- **SwiftLint** — lint checks.
- **swift build / type-check** — catch errors early.

Flag `print()` statements — use `os.Logger` or structured logging instead for
production code.
