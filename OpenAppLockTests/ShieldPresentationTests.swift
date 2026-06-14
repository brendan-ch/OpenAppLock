//
//  ShieldPresentationTests.swift
//  OpenAppLockTests
//

import Testing

@testable import OpenAppLock

@Suite("Shield presentation")
struct ShieldPresentationTests {
    @Test("Fully-blocked shield is generic and names no rule")
    func blockedIsGeneric() {
        let presentation = ShieldPresentation.blocked
        #expect(presentation.title == "App Blocked")
        #expect(presentation.subtitle == "This app is blocked by OpenAppLock.")
        #expect(presentation.secondaryButton == nil)
    }

    @Test("Open-limit shield with opens remaining shows counts and an Open button")
    func openLimitWithOpensRemaining() {
        let presentation = ShieldPresentation.openLimit(
            opensUsed: 2, maxOpens: 5, sessionMinutes: 15)
        // Title is generic — never the rule name.
        #expect(presentation.title == "App Blocked")
        #expect(presentation.subtitle.contains("Opened 2 of 5 times today"))
        #expect(presentation.subtitle.contains("15 minutes"))
        #expect(presentation.secondaryButton == "Open (3 left)")
    }

    @Test("A single remaining open reads in the singular")
    func openLimitSingularRemaining() {
        let presentation = ShieldPresentation.openLimit(
            opensUsed: 4, maxOpens: 5, sessionMinutes: 15)
        #expect(presentation.secondaryButton == "Open (1 left)")
    }

    @Test("Spent open-limit shield drops the Open button and reads as blocked")
    func openLimitExhausted() {
        let presentation = ShieldPresentation.openLimit(
            opensUsed: 5, maxOpens: 5, sessionMinutes: 15)
        #expect(presentation.title == "App Blocked")
        #expect(presentation.subtitle == "No opens left today — the block lifts tomorrow.")
        #expect(presentation.secondaryButton == nil)
    }

    @Test("Over-spending never yields a negative or non-nil Open button")
    func openLimitOverSpent() {
        let presentation = ShieldPresentation.openLimit(
            opensUsed: 9, maxOpens: 5, sessionMinutes: 15)
        #expect(presentation.secondaryButton == nil)
    }
}
