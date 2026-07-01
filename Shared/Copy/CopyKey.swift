import Foundation

/// The single index of every user-facing string in the app. The prose and all
/// typography live in `Shared/Localizable.xcstrings`, keyed by these raw values;
/// code only ever references the symbolic case. `nonisolated` so shield/monitor
/// extension code (outside the MainActor default) can resolve copy.
nonisolated enum CopyKey: String, CaseIterable {
    // Walking-skeleton seeds (more added per surface in later tasks):
    case onboardingRequesting = "onboarding.requesting"
    case ruleEditorCantPauseWhileActive = "ruleEditor.cantPauseWhileActive"

    /// Localized resource — the dedicated `Copy` table (`Shared/Copy.xcstrings`),
    /// `.main` bundle. A non-default table keeps our hand-authored symbolic keys
    /// isolated from Xcode's build-time string extraction, which only ever writes
    /// literal `Text("…")` strings to the default `Localizable` table. The catalog
    /// is embedded in every target, so `.main` resolves per process.
    var resource: LocalizedStringResource { LocalizedStringResource(String.LocalizationValue(rawValue), table: "Copy") }

    /// Resolved String for non-SwiftUI producers (shields, notifications, logic).
    var string: String { String(localized: resource) }

    /// Resolved + formatted for interpolated copy (placeholders live in the catalog value).
    func string(_ args: CVarArg...) -> String { String(format: string, arguments: args) }
}
