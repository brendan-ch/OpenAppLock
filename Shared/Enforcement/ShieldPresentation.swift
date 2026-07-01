//
//  ShieldPresentation.swift
//  OpenAppLock
//

/// The text a shield shows, decided independently of any UI type so it can be
/// unit tested. Shields never name the rule that blocks an app: when several
/// rules cover the same app the responsible rule can't be told apart, so every
/// shield carries the same generic "App Blocked" title. Open-limit shields add
/// their functional detail (remaining opens + an "Open" button) beneath it.
struct ShieldPresentation: Equatable {
    let title: String
    let subtitle: String
    /// Label for the secondary "Open" button, or `nil` when the shield offers
    /// no way through (a full block, or a spent open-limit budget).
    let secondaryButton: String?

    static let blockedTitle = CopyKey.shieldBlockedTitle.string

    /// A plain, fully-blocked app: no counts, no way through.
    static let blocked = ShieldPresentation(
        title: blockedTitle,
        subtitle: CopyKey.shieldBlockedSubtitle.string,
        secondaryButton: nil
    )

    /// An open-limit shield. While opens remain it shows the running count and
    /// an "Open (N left)" button; once spent it reads like a plain block.
    static func openLimit(
        opensUsed: Int, maxOpens: Int, sessionMinutes: Int
    ) -> ShieldPresentation {
        let remaining = max(0, maxOpens - opensUsed)
        guard remaining > 0 else {
            return ShieldPresentation(
                title: blockedTitle,
                subtitle: CopyKey.shieldNoOpensLeft.string,
                secondaryButton: nil
            )
        }
        return ShieldPresentation(
            title: blockedTitle,
            subtitle: CopyKey.shieldOpenLimitSubtitle.string(opensUsed, maxOpens, sessionMinutes),
            secondaryButton: remaining == 1
                ? CopyKey.shieldOpenButtonOne.string
                : CopyKey.shieldOpenButtonMany.string(remaining)
        )
    }
}
