import Foundation

/// The single index of every user-facing string in the app. The prose and all
/// typography live in `Shared/Copy.xcstrings`, keyed by these raw values;
/// code only ever references the symbolic case. `nonisolated` so shield/monitor
/// extension code (outside the MainActor default) can resolve copy.
nonisolated enum CopyKey: String, CaseIterable {
    // Walking-skeleton seeds (more added per surface in later tasks):
    case onboardingRequesting = "onboarding.requesting"
    case ruleEditorCantPauseWhileActive = "ruleEditor.cantPauseWhileActive"

    // MARK: - RuleEditorView (Task 2)
    case ruleEditorDisableAction = "ruleEditor.disableAction"
    case ruleEditorEnableAction = "ruleEditor.enableAction"
    case ruleEditorDeleteAction = "ruleEditor.deleteAction"
    case ruleEditorRuleActionsLabel = "ruleEditor.ruleActionsLabel"
    case ruleEditorAddRuleLabel = "ruleEditor.addRuleLabel"
    case ruleEditorDoneLabel = "ruleEditor.doneLabel"
    case ruleEditorAppListTitle = "ruleEditor.appListTitle"
    case ruleEditorRuleNamePlaceholder = "ruleEditor.ruleNamePlaceholder"
    case ruleEditorNameSectionHeader = "ruleEditor.nameSectionHeader"
    case ruleEditorFromLabel = "ruleEditor.fromLabel"
    case ruleEditorToLabel = "ruleEditor.toLabel"
    case ruleEditorDuringThisTimeHeader = "ruleEditor.duringThisTimeHeader"
    case ruleEditorModeLabel = "ruleEditor.modeLabel"
    case ruleEditorAppsAreBlockedHeader = "ruleEditor.appsAreBlockedHeader"
    case ruleEditorOnlyTheseAppsAllowedHeader = "ruleEditor.onlyTheseAppsAllowedHeader"
    case ruleEditorWhenIUseHeader = "ruleEditor.whenIUseHeader"
    case ruleEditorForThisLongHeader = "ruleEditor.forThisLongHeader"
    case ruleEditorWhenIOpenHeader = "ruleEditor.whenIOpenHeader"
    case ruleEditorMoreThanHeader = "ruleEditor.moreThanHeader"
    case ruleEditorOnTheseDaysHeader = "ruleEditor.onTheseDaysHeader"
    case ruleEditorUntilLabel = "ruleEditor.untilLabel"
    case ruleEditorTomorrowValue = "ruleEditor.tomorrowValue"
    case ruleEditorThenBlockAppHeader = "ruleEditor.thenBlockAppHeader"
    case ruleEditorHardModeToggle = "ruleEditor.hardModeToggle"
    case ruleEditorChooseAppListPlaceholder = "ruleEditor.chooseAppListPlaceholder"
    case ruleEditorAppListSummaryFormat = "ruleEditor.appListSummaryFormat"
    case ruleEditorDailyLabel = "ruleEditor.dailyLabel"
    case ruleEditorDailyTimeLimitAccessibilityLabel = "ruleEditor.dailyTimeLimitAccessibilityLabel"
    case ruleEditorDailyOpenLimitAccessibilityLabel = "ruleEditor.dailyOpenLimitAccessibilityLabel"
    case ruleEditorDailyMinutesAbbreviatedFormat = "ruleEditor.dailyMinutesAbbreviatedFormat"
    case ruleEditorDailyMinutesAccessibilityFormat = "ruleEditor.dailyMinutesAccessibilityFormat"
    case ruleEditorOpensCountFormat = "ruleEditor.opensCountFormat"

    // MARK: - RuleDetailSheet (Task 2)
    case ruleDetailGeneralSectionHeader = "ruleDetail.generalSectionHeader"
    case ruleDetailDetailsSectionHeader = "ruleDetail.detailsSectionHeader"
    case ruleDetailTodaysUsageLabel = "ruleDetail.todaysUsageLabel"
    case ruleDetailHardModeLockedNotice = "ruleDetail.hardModeLockedNotice"
    case ruleDetailCloseButton = "ruleDetail.closeButton"
    case ruleDetailEditButton = "ruleDetail.editButton"
    case ruleDetailPauseConfirmationTitleFormat = "ruleDetail.pauseConfirmationTitleFormat"
    case ruleDetailPauseConfirmationMessage = "ruleDetail.pauseConfirmationMessage"
    case ruleDetailPauseFor15MinutesAction = "ruleDetail.pauseFor15MinutesAction"
    case ruleDetailResumeBlockingAction = "ruleDetail.resumeBlockingAction"
    case ruleDetailDisableAction = "ruleDetail.disableAction"
    case ruleDetailEnableAction = "ruleDetail.enableAction"
    case ruleDetailDeleteAction = "ruleDetail.deleteAction"
    case ruleDetailRuleActionsLabel = "ruleDetail.ruleActionsLabel"
    case ruleDetailKindRowLabel = "ruleDetail.kindRowLabel"
    case ruleDetailStatusRowLabel = "ruleDetail.statusRowLabel"
    case ruleDetailDuringThisTimeRowLabel = "ruleDetail.duringThisTimeRowLabel"
    case ruleDetailOnTheseDaysRowLabel = "ruleDetail.onTheseDaysRowLabel"
    case ruleDetailPausingAllowedRowLabel = "ruleDetail.pausingAllowedRowLabel"
    case ruleDetailNoValue = "ruleDetail.noValue"
    case ruleDetailYesValue = "ruleDetail.yesValue"
    case ruleDetailWhenIUseRowLabel = "ruleDetail.whenIUseRowLabel"
    case ruleDetailForThisLongRowLabel = "ruleDetail.forThisLongRowLabel"
    case ruleDetailDailyMinutesSummaryFormat = "ruleDetail.dailyMinutesSummaryFormat"
    case ruleDetailThenBlockUntilRowLabel = "ruleDetail.thenBlockUntilRowLabel"
    case ruleDetailTomorrowValue = "ruleDetail.tomorrowValue"
    case ruleDetailWhenIOpenRowLabel = "ruleDetail.whenIOpenRowLabel"
    case ruleDetailMoreThanRowLabel = "ruleDetail.moreThanRowLabel"
    case ruleDetailOpensCountSummaryFormat = "ruleDetail.opensCountSummaryFormat"
    case ruleDetailNoAppsPlaceholder = "ruleDetail.noAppsPlaceholder"
    case ruleDetailAppListSummaryFormat = "ruleDetail.appListSummaryFormat"
    case ruleDetailUsageReportNavigationTitle = "ruleDetail.usageReportNavigationTitle"

    // MARK: - RulesListView (Task 2)
    case rulesListNavigationTitle = "rulesList.navigationTitle"
    case rulesListNewRuleButton = "rulesList.newRuleButton"
    case rulesListNoRulesYetTitle = "rulesList.noRulesYetTitle"
    case rulesListEmptyStateDescription = "rulesList.emptyStateDescription"

    // MARK: - NewRuleSheet (Task 2)
    case newRuleRuleTypeSectionHeader = "newRule.ruleTypeSectionHeader"
    case newRuleNavigationTitle = "newRule.navigationTitle"
    case newRuleCloseButton = "newRule.closeButton"
    case newRulePresetSummaryFormat = "newRule.presetSummaryFormat"

    // MARK: - SettingsView (Task 3)
    case settingsUninstallProtectionToggleLabel = "settings.uninstallProtectionToggleLabel"
    case settingsProtectionSectionHeader = "settings.protectionSectionHeader"
    case settingsUninstallProtectionLockedFooter = "settings.uninstallProtectionLockedFooter"
    case settingsUninstallProtectionUnlockedFooter = "settings.uninstallProtectionUnlockedFooter"
    case settingsAppListsRowLabel = "settings.appListsRowLabel"
    case settingsNotificationsRowLabel = "settings.notificationsRowLabel"
    case settingsLogsRowLabel = "settings.logsRowLabel"
    case settingsMoreSettingsSectionHeader = "settings.moreSettingsSectionHeader"
    case settingsNavigationTitle = "settings.navigationTitle"
    case settingsGithubLinkLabel = "settings.githubLinkLabel"
    case settingsWebsiteLinkLabel = "settings.websiteLinkLabel"
    case settingsAboutSectionHeader = "settings.aboutSectionHeader"

    // MARK: - NotificationSettingsView (Task 3)
    case notificationsNavigationTitle = "notifications.navigationTitle"
    case notificationsAllowedStatusLabel = "notifications.allowedStatusLabel"
    case notificationsAllowButton = "notifications.allowButton"
    case notificationsOpenSettingsButton = "notifications.openSettingsButton"
    case notificationsPermissionSectionHeader = "notifications.permissionSectionHeader"
    case notificationsDeniedFooter = "notifications.deniedFooter"
    case notificationsScheduleStartToggleLabel = "notifications.scheduleStartToggleLabel"
    case notificationsTimeLimitToggleLabel = "notifications.timeLimitToggleLabel"
    case notificationsNotifyMeSectionHeader = "notifications.notifyMeSectionHeader"
    case notificationsFooter = "notifications.footer"

    // MARK: - DiagnosticLogsView (Task 3)
    case diagnosticsNoLogsMessage = "diagnostics.noLogsMessage"
    case diagnosticsDaysSectionHeader = "diagnostics.daysSectionHeader"
    case diagnosticsDaysSectionFooter = "diagnostics.daysSectionFooter"
    case diagnosticsClearAllLogsButton = "diagnostics.clearAllLogsButton"
    case diagnosticsClearLogsConfirmationTitle = "diagnostics.clearLogsConfirmationTitle"
    case diagnosticsCancelButton = "diagnostics.cancelButton"
    case diagnosticsClearLogsConfirmationMessage = "diagnostics.clearLogsConfirmationMessage"
    case diagnosticsNavigationTitle = "diagnostics.navigationTitle"
    case diagnosticsNoEntriesPlaceholder = "diagnostics.noEntriesPlaceholder"

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
