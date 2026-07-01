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

    // MARK: - App Lists (Task 4) — shared across AppListEditorView,
    // AppListLibraryView, AppListDetailView, ManageAppListsView (one feature
    // domain, per the design spec's `appLists.` prefix).
    case appListsEditAppsLabel = "appLists.editAppsLabel"
    case appListsAppsSectionHeader = "appLists.appsSectionHeader"
    case appListsNewListLabel = "appLists.newListLabel"

    // MARK: - AppListEditorView (Task 4)
    case appListsEditorNameFieldPlaceholder = "appLists.editorNameFieldPlaceholder"
    case appListsEditorNameSectionHeader = "appLists.editorNameSectionHeader"
    case appListsEditorNoAppsYetMessage = "appLists.editorNoAppsYetMessage"
    case appListsOneAppCountLabel = "appLists.oneAppCountLabel"
    case appListsAppsCountFormat = "appLists.appsCountFormat"
    case appListsEditListLabel = "appLists.editListLabel"
    case appListsCloseButtonLabel = "appLists.closeButtonLabel"
    case appListsDiscardChangesConfirmationTitle = "appLists.discardChangesConfirmationTitle"
    case appListsDiscardChangesAction = "appLists.discardChangesAction"
    case appListsKeepEditingAction = "appLists.keepEditingAction"
    case appListsUnsavedEditsMessage = "appLists.unsavedEditsMessage"
    case appListsSaveListAccessibilityLabel = "appLists.saveListAccessibilityLabel"
    case appListsUntitledListDefaultName = "appLists.untitledListDefaultName"

    // MARK: - AppListLibraryView (Task 4)
    case appListsLibraryEmptyStateTitle = "appLists.libraryEmptyStateTitle"
    case appListsLibraryEmptyStateDescription = "appLists.libraryEmptyStateDescription"
    case appListsLibraryYourAppListsSectionHeader = "appLists.libraryYourAppListsSectionHeader"
    case appListsLibraryLockedFooter = "appLists.libraryLockedFooter"
    case appListsLibraryDeletionBlockedAlertTitle = "appLists.libraryDeletionBlockedAlertTitle"
    case appListsOkButtonLabel = "appLists.okButtonLabel"
    case appListsLibraryDeletionBlockedAlertMessage = "appLists.libraryDeletionBlockedAlertMessage"
    case appListsLibraryViewButtonLabel = "appLists.libraryViewButtonLabel"
    case appListsLibraryEditButtonLabel = "appLists.libraryEditButtonLabel"
    case appListsLibraryDeleteButtonLabel = "appLists.libraryDeleteButtonLabel"

    // MARK: - AppListDetailView (Task 4)
    case appListsDetailEmptyMessage = "appLists.detailEmptyMessage"
    case appListsDetailReadOnlyFooter = "appLists.detailReadOnlyFooter"

    // MARK: - ManageAppListsView (Task 4)
    case appListsManageNavigationTitle = "appLists.manageNavigationTitle"

    // MARK: - HomeView (Task 5)
    case homeNavigationTitle = "home.navigationTitle"
    case homeNothingBlockingMessage = "home.nothingBlockingMessage"
    case homeCurrentlyBlockingSectionHeader = "home.currentlyBlockingSectionHeader"
    case homeActiveRulesSectionHeader = "home.activeRulesSectionHeader"

    // MARK: - OnboardingView (Task 5) — onboarding.requesting migrated in Task 1
    case onboardingWelcomeTitle = "onboarding.welcomeTitle"
    case onboardingWelcomeDescription = "onboarding.welcomeDescription"
    case onboardingAllowScreenTime = "onboarding.allowScreenTime"
    case onboardingScreenTimeFrameworkBullet = "onboarding.screenTimeFrameworkBullet"
    case onboardingActivityStaysPrivateBullet = "onboarding.activityStaysPrivateBullet"
    case onboardingChangeAnytimeBullet = "onboarding.changeAnytimeBullet"
    case onboardingAccessDeclinedMessage = "onboarding.accessDeclinedMessage"
    case onboardingOpenSettingsButton = "onboarding.openSettingsButton"
    case onboardingContinueButton = "onboarding.continueButton"

    // MARK: - Nav shell: MainSidebarView + AppSection (Task 5)
    case navAppTitle = "nav.appTitle"
    case navHomeSectionTitle = "nav.homeSectionTitle"
    case navRulesSectionTitle = "nav.rulesSectionTitle"
    case navSettingsSectionTitle = "nav.settingsSectionTitle"

    // MARK: - DayOfWeekPicker (Task 5)
    case dayPickerPreviewSectionHeader = "dayPicker.previewSectionHeader"

    // MARK: - RuleStatus (Task 6)
    case statusDisabled = "status.disabled"
    case statusNoDaysSelected = "status.noDaysSelected"
    case statusResumesIn = "status.resumesIn"
    case statusActiveLeft = "status.activeLeft"
    case statusStartsIn = "status.startsIn"
    case statusCountdownMinutes = "status.countdownMinutes"
    case statusCountdownHours = "status.countdownHours"
    case statusCountdownDays = "status.countdownDays"
    case statusBlockedUntilTomorrow = "status.blockedUntilTomorrow"

    // MARK: - UsageDisplay (Task 6)
    case usageMinutesPerDay = "usage.minutesPerDay"
    case usageOpensPerDay = "usage.opensPerDay"
    case usageSubtitleSeparator = "usage.subtitleSeparator"

    // MARK: - RuleKind (Task 6)
    case ruleKindScheduleDisplayName = "ruleKind.scheduleDisplayName"
    case ruleKindTimeLimitDisplayName = "ruleKind.timeLimitDisplayName"
    case ruleKindOpenLimitDisplayName = "ruleKind.openLimitDisplayName"
    case ruleKindScheduleExampleText = "ruleKind.scheduleExampleText"
    case ruleKindTimeLimitExampleText = "ruleKind.timeLimitExampleText"
    case ruleKindOpenLimitExampleText = "ruleKind.openLimitExampleText"

    // MARK: - Weekday (Task 6)
    case weekdayShortLabelS = "weekday.shortLabelS"
    case weekdayShortLabelM = "weekday.shortLabelM"
    case weekdayShortLabelT = "weekday.shortLabelT"
    case weekdayShortLabelW = "weekday.shortLabelW"
    case weekdayShortLabelF = "weekday.shortLabelF"
    case weekdaySundayAbbreviation = "weekday.sundayAbbreviation"
    case weekdayMondayAbbreviation = "weekday.mondayAbbreviation"
    case weekdayTuesdayAbbreviation = "weekday.tuesdayAbbreviation"
    case weekdayWednesdayAbbreviation = "weekday.wednesdayAbbreviation"
    case weekdayThursdayAbbreviation = "weekday.thursdayAbbreviation"
    case weekdayFridayAbbreviation = "weekday.fridayAbbreviation"
    case weekdaySaturdayAbbreviation = "weekday.saturdayAbbreviation"
    case weekdayEveryDaySummary = "weekday.everyDaySummary"
    case weekdayWeekdaysSummary = "weekday.weekdaysSummary"
    case weekdayWeekendsSummary = "weekday.weekendsSummary"
    case weekdayNeverSummary = "weekday.neverSummary"

    // MARK: - RulePreset (Task 6)
    case presetMorningFocusName = "preset.morningFocusName"
    case presetDeepWorkName = "preset.deepWorkName"
    case presetEveningResetName = "preset.eveningResetName"
    case presetLightsOutName = "preset.lightsOutName"
    case presetFamilyDinnerName = "preset.familyDinnerName"
    case presetScreenFreeSundayName = "preset.screenFreeSundayName"
    case presetFocusSectionTitle = "preset.focusSectionTitle"
    case presetFocusSectionSubtitle = "preset.focusSectionSubtitle"
    case presetRestSectionTitle = "preset.restSectionTitle"
    case presetRestSectionSubtitle = "preset.restSectionSubtitle"
    case presetBalanceSectionTitle = "preset.balanceSectionTitle"
    case presetBalanceSectionSubtitle = "preset.balanceSectionSubtitle"

    // MARK: - ShieldPresentation (Task 7)
    case shieldBlockedTitle = "shield.blockedTitle"
    case shieldBlockedSubtitle = "shield.blockedSubtitle"
    case shieldNoOpensLeft = "shield.noOpensLeft"
    case shieldOpenLimitSubtitle = "shield.openLimit.subtitle"
    case shieldOpenButtonOne = "shield.openButtonOne"
    case shieldOpenButtonMany = "shield.openButtonMany"
    case shieldPrimaryButtonLabel = "shield.primaryButtonLabel"

    // MARK: - LimitWarningDecision (Task 7)
    case notificationTimeLimitWarningTitle = "notification.timeLimitWarningTitle"
    case notificationTimeLimitWarningBodyFormat = "notification.timeLimitWarningBodyFormat"

    // MARK: - UsageReportFormatter + RuleUsageReport (Task 7)
    case usageReportNoUsageToday = "usageReport.noUsageToday"
    case usageReportTodayTotalFormat = "usageReport.todayTotalFormat"
    case usageReportDurationHoursMinutesFormat = "usageReport.durationHoursMinutesFormat"
    case usageReportDurationHoursFormat = "usageReport.durationHoursFormat"
    case usageReportDurationMinutesFormat = "usageReport.durationMinutesFormat"
    case usageReportUnderAMinute = "usageReport.underAMinute"
    case usageReportUnknownAppName = "usageReport.unknownAppName"

    // MARK: - RuleKind stragglers (Task 8)
    case ruleKindDefaultNameSchedule = "ruleKind.defaultNameSchedule"
    case ruleKindDefaultNameTimeLimit = "ruleKind.defaultNameTimeLimit"
    case ruleKindDefaultNameOpenLimit = "ruleKind.defaultNameOpenLimit"
    case selectionModeBlock = "selectionMode.block"
    case selectionModeAllowOnly = "selectionMode.allowOnly"

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
