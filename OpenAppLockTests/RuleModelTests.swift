//
//  RuleModelTests.swift
//  OpenAppLockTests
//

import Foundation
import SwiftData
import Testing

@testable import OpenAppLock

@MainActor
@Suite("BlockingRule model & persistence")
struct RuleModelTests {
    @Test("Defaults match the documented new-rule defaults")
    func defaults() {
        let rule = BlockingRule(name: "In the Zone")
        #expect(rule.kind == .schedule)
        #expect(rule.isEnabled)
        #expect(!rule.hardMode)
        #expect(rule.selectionMode == .block)
        #expect(rule.days == Weekday.weekdays)
        #expect(rule.startMinutes == 9 * 60)
        #expect(rule.endMinutes == 17 * 60)
        #expect(rule.pausedUntil == nil)
    }

    @Test("Days survive the raw-storage round trip")
    func daysRoundTrip() {
        let rule = BlockingRule(name: "Test")
        rule.days = [.sunday, .wednesday, .saturday]
        #expect(rule.days == [.sunday, .wednesday, .saturday])
        #expect(rule.dayNumbers == [1, 4, 7])
    }

    @Test("Kind and selection mode survive raw storage, with safe fallbacks")
    func enumRoundTrip() {
        let rule = BlockingRule(
            name: "Test", configuration: .schedule(ScheduleConfig(selectionMode: .allowOnly)))
        #expect(rule.kind == .schedule)
        #expect(rule.selectionMode == .allowOnly)
        rule.kindRaw = "garbage"
        rule.selectionModeRaw = "garbage"
        #expect(rule.kind == .schedule)
        #expect(rule.selectionMode == .block)
    }

    @Test("Limit kinds can never carry Schedule-only options")
    func limitKindsHaveNoScheduleOptions() {
        let timeLimit = BlockingRule(
            name: "Time Keeper", configuration: .timeLimit(TimeLimitConfig(dailyLimitMinutes: 30)))
        #expect(timeLimit.kind == .timeLimit)
        #expect(timeLimit.selectionMode == .block)
        #expect(timeLimit.dailyLimitMinutes == 30)

        let openLimit = BlockingRule(
            name: "Gate Keeper", configuration: .openLimit(OpenLimitConfig(maxOpens: 3)))
        #expect(openLimit.kind == .openLimit)
        #expect(openLimit.selectionMode == .block)
        #expect(openLimit.maxOpens == 3)
    }

    @Test("Configuration round-trips through the model's raw storage")
    func configurationRoundTrip() {
        let config = RuleConfiguration.schedule(
            ScheduleConfig(
                startMinutes: 22 * 60, endMinutes: 6 * 60,
                selectionMode: .allowOnly))
        let rule = BlockingRule(name: "Deep Sleep", configuration: config)
        #expect(rule.configuration == config)
        #expect(rule.startMinutes == 22 * 60)
        #expect(rule.selectionMode == .allowOnly)
    }

    @Test("Rules persist and fetch through SwiftData")
    func persistence() throws {
        let context = try makeInMemoryContext()
        let rule = BlockingRule(
            name: "Deep Sleep",
            configuration: .schedule(ScheduleConfig(startMinutes: 22 * 60, endMinutes: 6 * 60)),
            hardMode: true,
            days: Weekday.everyDay
        )
        context.insert(rule)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BlockingRule>())
        #expect(fetched.count == 1)
        let saved = try #require(fetched.first)
        #expect(saved.name == "Deep Sleep")
        #expect(saved.hardMode)
        #expect(saved.days == Weekday.everyDay)
        #expect(saved.schedule.crossesMidnight)
    }
}

@MainActor
@Suite("RuleDraft")
struct RuleDraftTests {
    @Test("New drafts use the kind's defaults")
    func newDraftDefaults() {
        let draft = RuleDraft(kind: .timeLimit)
        #expect(draft.name == "Time Keeper")
        #expect(draft.kind == .timeLimit)
        #expect(draft.timeLimitConfig.dailyLimitMinutes == 45)
        #expect(draft.days == Weekday.weekdays)
        #expect(!draft.hardMode)
    }

    @Test("Draft → rule → draft round-trips every field")
    func roundTrip() throws {
        let context = try makeInMemoryContext()
        let list = AppList(name: "Distractions", selectionCount: 3)
        context.insert(list)

        var draft = RuleDraft(kind: .schedule)
        draft.name = "Locked In"
        draft.days = Weekday.everyDay
        draft.configuration = .schedule(
            ScheduleConfig(
                startMinutes: 22 * 60, endMinutes: 6 * 60,
                selectionMode: .allowOnly))
        draft.hardMode = true
        draft.appList = list

        let rule = draft.insertRule(into: context)
        #expect(rule.selectionMode == .allowOnly)
        #expect(RuleDraft(rule: rule) == draft)
    }

    @Test("A limit draft cannot carry Schedule-only options")
    func limitDraftHasNoScheduleOptions() {
        let draft = RuleDraft(kind: .openLimit)
        // The configuration is an open-limit case, so there is structurally no
        // selection mode to set.
        #expect(draft.configuration.scheduleConfig == nil)
        #expect(draft.openLimitConfig.maxOpens == 5)

        let rule = BlockingRule(name: draft.name, configuration: draft.configuration)
        #expect(rule.selectionMode == .block)
    }

    @Test("Applying a draft updates an existing rule")
    func applyToExisting() throws {
        let context = try makeInMemoryContext()
        let rule = BlockingRule(name: "Old Name")
        context.insert(rule)
        var draft = RuleDraft(rule: rule)
        draft.name = "New Name"
        draft.hardMode = true
        draft.apply(to: rule)
        #expect(rule.name == "New Name")
        #expect(rule.hardMode)
    }

    @Test("Sanitizing trims whitespace and falls back to the kind default")
    func sanitizedName() {
        var draft = RuleDraft(kind: .schedule)
        draft.name = "  Deep Work  "
        #expect(draft.sanitized().name == "Deep Work")

        draft.name = "   "
        #expect(draft.sanitized().name == "In the Zone")

        var limitDraft = RuleDraft(kind: .timeLimit)
        limitDraft.name = ""
        #expect(limitDraft.sanitized().name == "Time Keeper")
    }

    @Test("Preset drafts copy the preset's schedule")
    func presetDraft() throws {
        let preset = try #require(
            RulePresetSection.all
                .flatMap(\.presets)
                .first { $0.id == "lights-out" }
        )
        let draft = RuleDraft(preset: preset)
        #expect(draft.name == "Lights Out")
        #expect(draft.scheduleConfig.startMinutes == 23 * 60)
        #expect(draft.scheduleConfig.endMinutes == 6 * 60 + 30)
        #expect(draft.kind == .schedule)
    }
}

@MainActor
@Suite("Weekday summaries")
struct WeekdayTests {
    @Test("Named sets")
    func namedSets() {
        #expect(Weekday.weekdays.summary == "Weekdays")
        #expect(Weekday.weekends.summary == "Weekends")
        #expect(Weekday.everyDay.summary == "Every day")
        #expect(Set<Weekday>().summary == "Never")
    }

    @Test("Custom sets list days in display order")
    func customSets() {
        let days: Set<Weekday> = [.friday, .monday, .wednesday]
        #expect(days.summary == "Mon, Wed, Fri")
    }

    @Test("Picker display order starts on Sunday")
    func displayOrder() {
        #expect(Weekday.displayOrder.first == .sunday)
        #expect(Weekday.displayOrder.count == 7)
        #expect(Weekday.displayOrder.map(\.shortLabel) == ["S", "M", "T", "W", "T", "F", "S"])
    }
}
