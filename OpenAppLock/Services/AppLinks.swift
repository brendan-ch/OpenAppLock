//
//  AppLinks.swift
//  OpenAppLock
//

import Foundation

/// The one place the app reads its outbound URLs (GitHub repo, marketing site).
///
/// The values are *configuration, not code*: they come from the
/// `OAL_GITHUB_URL` / `OAL_WEBSITE_URL` user-defined build settings (see
/// `Config/Shared.xcconfig`), surfaced to the runtime through the generated
/// `Info.plist` via `INFOPLIST_KEY_OALGitHubURL` / `INFOPLIST_KEY_OALWebsiteURL`.
/// Point them at the real destinations by editing the build settings — no code
/// change needed.
///
/// Read them anywhere via ``gitHub`` / ``website``. Both are `nil` when the
/// setting is unset, blank, or unparseable, so callers can simply omit the row.
enum AppLinks {
    /// Info.plist keys the build settings feed into (kept in sync with
    /// `INFOPLIST_KEY_*` in `Config/Shared.xcconfig`).
    static let gitHubInfoKey = "OALGitHubURL"
    static let websiteInfoKey = "OALWebsiteURL"

    /// The project's GitHub repository, or `nil` when unconfigured.
    static var gitHub: URL? { url(from: Bundle.main.object(forInfoDictionaryKey: gitHubInfoKey)) }

    /// The project's marketing website, or `nil` when unconfigured.
    static var website: URL? { url(from: Bundle.main.object(forInfoDictionaryKey: websiteInfoKey)) }

    /// Turns a raw Info.plist value into a usable URL. Pure and side-effect
    /// free so it can be unit-tested directly: non-string, blank, or
    /// whitespace-only values (and anything `URL` can't parse) become `nil`.
    static func url(from rawValue: Any?) -> URL? {
        guard let string = rawValue as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
