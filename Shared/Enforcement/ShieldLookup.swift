//
//  ShieldLookup.swift
//  OpenAppLock
//

import FamilyControls
import Foundation
import ManagedSettings

/// Matches shielded tokens back to the rule that shields them, so the shield
/// UI can offer "Open" with the right counts for open-limit rules.
///
/// When several rules cover the same token, the Open offer is arbitrated:
/// it is withheld whenever another covering rule is actively blocking, because
/// granting an open clears only the open-limit rule's own store — the other
/// rule's shield would keep the app blocked, stranding the user behind a
/// re-presented shield with one of their limited opens wasted. In that state
/// the plain blocked shield is the truthful one.
enum ShieldLookup {
    /// The open-limit rule whose "Open" offer is valid for a token covered by
    /// the given rules: the first enabled open-limit rule, unless another
    /// covering rule is actively blocking right now (per `activation`, the
    /// shared source of temporal truth). An open-limit rule inside its granted
    /// open session has its store cleared, so it is not treated as blocking.
    ///
    /// The candidate's *own* blocking state (spent opens) never suppresses it:
    /// the exhausted shield still needs the snapshot to render its counts.
    static func openLimitSnapshot(
        amongCovering covering: [RuleSnapshotDTO],
        usage: (UUID) -> RuleUsageDTO,
        hasActiveOpenSession: (UUID) -> Bool,
        at now: Date, calendar: Calendar = .current
    ) -> RuleSnapshotDTO? {
        guard
            let candidate = covering.first(where: { $0.kind == .openLimit && $0.isEnabled })
        else { return nil }
        let anotherRuleBlocks = covering.contains { other in
            other.id != candidate.id
                && !hasActiveOpenSession(other.id)
                && other.activation(usage: usage(other.id), at: now, calendar: calendar)
                    .isBlocking
        }
        return anotherRuleBlocks ? nil : candidate
    }

    /// `orCategory` is the category the shield was presented under, when known
    /// (the `configuration(shielding:in:)` overload): a rule shielding that
    /// category covers the app by membership even though the opaque application
    /// token can never match its `categoryTokens`, so it must join the covering
    /// set for the arbitration to see category-based blockers.
    static func openLimitSnapshot(
        containingApplication token: ApplicationToken,
        orCategory categoryToken: ActivityCategoryToken? = nil,
        in snapshots: [RuleSnapshotDTO],
        usage: (UUID) -> RuleUsageDTO,
        hasActiveOpenSession: (UUID) -> Bool,
        at now: Date, calendar: Calendar = .current
    ) -> RuleSnapshotDTO? {
        openLimitSnapshot(
            amongCovering: snapshots.filter { snapshot in
                covers(snapshot, applicationToken: token)
                    || categoryToken.map { covers(snapshot, categoryToken: $0) } == true
            },
            usage: usage, hasActiveOpenSession: hasActiveOpenSession,
            at: now, calendar: calendar)
    }

    static func openLimitSnapshot(
        containingCategory token: ActivityCategoryToken, in snapshots: [RuleSnapshotDTO],
        usage: (UUID) -> RuleUsageDTO,
        hasActiveOpenSession: (UUID) -> Bool,
        at now: Date, calendar: Calendar = .current
    ) -> RuleSnapshotDTO? {
        openLimitSnapshot(
            amongCovering: snapshots.filter { covers($0, categoryToken: token) },
            usage: usage, hasActiveOpenSession: hasActiveOpenSession,
            at: now, calendar: calendar)
    }

    /// Whether the rule's shield would reach this application token when it
    /// shields (mode inversion in `selectionCoversApplication`).
    private static func covers(
        _ snapshot: RuleSnapshotDTO, applicationToken token: ApplicationToken
    ) -> Bool {
        selectionCoversApplication(
            mode: snapshot.selectionMode,
            selectionContainsToken: AppSelectionCodec.decode(snapshot.selectionData)
                .applicationTokens.contains(token))
    }

    /// Category-token variant of `covers` (mode semantics in
    /// `selectionCoversCategory`).
    private static func covers(
        _ snapshot: RuleSnapshotDTO, categoryToken token: ActivityCategoryToken
    ) -> Bool {
        selectionCoversCategory(
            mode: snapshot.selectionMode,
            selectionContainsToken: AppSelectionCodec.decode(snapshot.selectionData)
                .categoryTokens.contains(token))
    }

    /// Pure mode semantics for application coverage, split out because the
    /// opaque tokens can't be fabricated in unit tests. An Allow-Only rule
    /// shields everything *except* its selection (`.all(except:)` — see
    /// `ShieldController`), so it covers exactly the tokens outside it.
    static func selectionCoversApplication(
        mode: SelectionMode, selectionContainsToken: Bool
    ) -> Bool {
        switch mode {
        case .block: selectionContainsToken
        case .allowOnly: !selectionContainsToken
        }
    }

    /// Pure mode semantics for category coverage. An Allow-Only rule's
    /// `.all(except:)` shields every category (its exceptions are individual
    /// applications), so it covers any category token.
    static func selectionCoversCategory(
        mode: SelectionMode, selectionContainsToken: Bool
    ) -> Bool {
        switch mode {
        case .block: selectionContainsToken
        case .allowOnly: true
        }
    }
}
