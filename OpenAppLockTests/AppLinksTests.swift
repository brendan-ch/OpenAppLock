//
//  AppLinksTests.swift
//  OpenAppLockTests
//

import Foundation
import Testing

@testable import OpenAppLock

/// `AppLinks` is the single place the app reads its outbound URLs (GitHub repo,
/// marketing site). The values arrive from `INFOPLIST_KEY_*` build settings, so
/// these tests cover both the pure parsing seam and the real Info.plist pipeline
/// (the unit-test target is app-hosted, so `Bundle.main` is the app bundle).
@MainActor
@Suite("AppLinks")
struct AppLinksTests {
    @Test("A well-formed URL string parses")
    func parsesValidURL() {
        let url = AppLinks.url(from: "https://example.com/path")
        #expect(url?.absoluteString == "https://example.com/path")
    }

    @Test("Surrounding whitespace is trimmed before parsing")
    func trimsWhitespace() {
        let url = AppLinks.url(from: "  https://example.com  \n")
        #expect(url?.absoluteString == "https://example.com")
    }

    @Test("Blank, whitespace-only, missing, and non-string values yield nil")
    func rejectsUnusableValues() {
        #expect(AppLinks.url(from: "") == nil)
        #expect(AppLinks.url(from: "   \n ") == nil)
        #expect(AppLinks.url(from: nil) == nil)
        #expect(AppLinks.url(from: 42) == nil)
    }

    @Test("GitHub link is configured through the build settings → Info.plist pipeline")
    func gitHubConfigured() {
        let url = AppLinks.gitHub
        #expect(url != nil)
        // A full URL, not a "https:" fragment — guards against the xcconfig
        // "//"-comment truncation the `$(SLASH)` indirection is there to avoid.
        #expect(url?.absoluteString.contains("://") == true)
    }

    @Test("Website link is configured through the build settings → Info.plist pipeline")
    func websiteConfigured() {
        let url = AppLinks.website
        #expect(url != nil)
        #expect(url?.absoluteString.contains("://") == true)
    }
}
