//
//  TestSupport.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData

@testable import OpenAppLock

/// One in-memory ModelContainer shared by the whole test process.
///
/// Repeatedly creating containers for this schema (inverse relationships)
/// trips an intermittent EXC_BREAKPOINT inside SwiftData's configuration
/// setup — observed both in test runs and in a sequential snippet that made
/// six containers. Tests therefore share a single container; isolation comes
/// from a fresh ModelContext plus a data wipe per test.
@MainActor
private let sharedTestContainer: ModelContainer = {
    do {
        return try ModelContainer(
            for: Schema([BlockingRule.self, AppList.self]),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Could not create the shared test ModelContainer: \(error)")
    }
}()

/// Fresh, empty SwiftData context for model tests. The wipe deletes object
/// by object — batch `delete(model:)` refuses to fire the appList nullify
/// inverse ("Constraint trigger violation").
@MainActor
func makeInMemoryContext() throws -> ModelContext {
    let context = ModelContext(sharedTestContainer)
    for rule in try context.fetch(FetchDescriptor<BlockingRule>()) {
        context.delete(rule)
    }
    for list in try context.fetch(FetchDescriptor<AppList>()) {
        context.delete(list)
    }
    try context.save()
    return context
}

/// Fixed UTC gregorian calendar so schedule math is deterministic regardless
/// of the machine running the tests.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Builds a date in the UTC test calendar. 2025-01-06 is a Monday; the tests
/// use that week (Jan 6–12, 2025) as their anchor.
func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
) -> Date {
    utc.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

/// Monday of the anchor week.
enum AnchorWeek {
    static let monday = (year: 2025, month: 1, day: 6)
    static let tuesday = (year: 2025, month: 1, day: 7)
    static let wednesday = (year: 2025, month: 1, day: 8)
    static let saturday = (year: 2025, month: 1, day: 11)
    static let sunday = (year: 2025, month: 1, day: 12)
    static let nextMonday = (year: 2025, month: 1, day: 13)
}
