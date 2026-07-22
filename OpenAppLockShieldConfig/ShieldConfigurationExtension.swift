//
//  ShieldConfigurationExtension.swift
//  OpenAppLockShieldConfig
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the system shield. Apps under an open-limit rule show how many
/// opens were used and offer an "Open" secondary button while opens remain;
/// everything else gets a plain blocked shield — including an open-limit app
/// while *another* covering rule is actively blocking it, since an open grant
/// could not lift that rule's shield (`ShieldLookup` arbitrates). Shields never
/// name a rule — the text is decided by the pure `ShieldPresentation`.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        guard let token = application.token else { return configuration(for: .blocked) }
        return configuration(forApplicationToken: token)
    }

    override func configuration(
        shielding application: Application, in category: ActivityCategory
    ) -> ShieldConfiguration {
        guard let token = application.token else { return configuration(for: .blocked) }
        // The category is the reason this shield exists; passing it lets the
        // arbitration see rules that block the app by category membership.
        return configuration(forApplicationToken: token, categoryToken: category.token)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(for: .blocked)
    }

    override func configuration(
        shielding webDomain: WebDomain, in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(for: .blocked)
    }

    private func configuration(
        forApplicationToken token: ApplicationToken,
        categoryToken: ActivityCategoryToken? = nil
    ) -> ShieldConfiguration {
        let snapshots = RuleSnapshotUserDefaultsStore().load()
        let ledger = UsageLedger()
        let sessions = OpenSessionStore()
        let now = Date.now
        guard
            let snapshot = ShieldLookup.openLimitSnapshot(
                containingApplication: token, orCategory: categoryToken, in: snapshots,
                usage: { ledger.usage(for: $0, onDayContaining: now) },
                hasActiveOpenSession: { sessions.hasActiveSession(for: $0, at: now) },
                at: now)
        else {
            return configuration(for: .blocked)
        }
        let usage = ledger.usage(for: snapshot.id, onDayContaining: now)
        return configuration(
            for: .openLimit(
                opensUsed: usage.opensUsed,
                maxOpens: snapshot.maxOpens,
                sessionMinutes: MonitoringPlan.openSessionMinutes))
    }

    private func configuration(for presentation: ShieldPresentation) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            title: .init(text: presentation.title, color: .label),
            subtitle: .init(text: presentation.subtitle, color: .secondaryLabel),
            primaryButtonLabel: .init(text: CopyKey.shieldPrimaryButtonLabel.string, color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: presentation.secondaryButton.map {
                .init(text: $0, color: .systemBlue)
            }
        )
    }
}
