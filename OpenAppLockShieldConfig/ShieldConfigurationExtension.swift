//
//  ShieldConfigurationExtension.swift
//  OpenAppLockShieldConfig
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customizes the system shield. Apps under an open-limit rule show how many
/// opens were used and offer an "Open" secondary button while opens remain;
/// everything else gets a plain blocked shield. Shields never name a rule — the
/// text is decided by the pure `ShieldPresentation`.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        guard let token = application.token else { return configuration(for: .blocked) }
        return configuration(forApplicationToken: token)
    }

    override func configuration(
        shielding application: Application, in category: ActivityCategory
    ) -> ShieldConfiguration {
        guard let token = application.token else { return configuration(for: .blocked) }
        return configuration(forApplicationToken: token)
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
        forApplicationToken token: ApplicationToken
    ) -> ShieldConfiguration {
        let snapshots = RuleSnapshotStore().load()
        guard
            let snapshot = ShieldLookup.openLimitSnapshot(
                containingApplication: token, in: snapshots)
        else {
            return configuration(for: .blocked)
        }
        let usage = UsageLedger().usage(for: snapshot.id, onDayContaining: .now)
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
            primaryButtonLabel: .init(text: "OK", color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: presentation.secondaryButton.map {
                .init(text: $0, color: .systemBlue)
            }
        )
    }
}
