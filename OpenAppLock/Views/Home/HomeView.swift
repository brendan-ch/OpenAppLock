//
//  HomeView.swift
//  OpenAppLock
//

import SwiftData
import SwiftUI

/// The Home tab: what's blocking right now, and live usage for today's limit
/// rules. The rule list and rule creation live on the Rules tab.
struct HomeView: View {
    @Environment(RuleEnforcer.self) private var enforcer
    @Query(sort: \BlockingRule.createdAt) private var rules: [BlockingRule]

    @State private var unblockCandidate: BlockingRule?
    @State private var hardModeBlockedAttempt = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                homeList(now: timeline.date)
            }
            .navigationTitle("Home")
        }
        .confirmationDialog(
            "Unblock \(unblockCandidate?.name ?? "")?",
            isPresented: Binding(
                get: { unblockCandidate != nil },
                set: { if !$0 { unblockCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unblock", role: .destructive) {
                if let rule = unblockCandidate {
                    RulePolicy.unblock(rule, usage: enforcer.usage(for: rule.dto))
                    enforcer.refresh(rules: rules)
                }
                unblockCandidate = nil
            }
        } message: {
            Text("Blocking resumes with the rule's next window.")
        }
        .alert("Hard Mode is on", isPresented: $hardModeBlockedAttempt) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This block can't be lifted until it ends.")
        }
    }

    private func homeList(now: Date) -> some View {
        List {
            blockingSection(now: now)
            usageSection(now: now)
        }
    }

    /// Status with the day's usage folded in, so limit rules whose budget is
    /// spent count as actively blocking.
    private func liveStatus(for rule: BlockingRule, now: Date) -> RuleStatus {
        let dto = rule.dto
        return dto.status(at: now, usage: enforcer.usage(for: dto, at: now))
    }

    // MARK: - Currently Blocking

    @ViewBuilder
    private func blockingSection(now: Date) -> some View {
        let blocking = rules.filter { liveStatus(for: $0, now: now).isActive }
        Section {
            if blocking.isEmpty {
                Text("Nothing is blocking right now.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("nothingBlockedLabel")
            } else {
                ForEach(blocking) { rule in
                    blockingRow(for: rule, now: now)
                }
            }
        } header: {
            Text("Currently Blocking").textCase(nil)
        }
    }

    /// A blocking rule: leading kind icon, name, and a "<Type> · <context>"
    /// subtitle (a schedule shows its countdown, a limit its usage). Trailing
    /// affordance: a lock when Hard Mode (the block can't be lifted), otherwise
    /// an Unblock button.
    private func blockingRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsage()
        let status = liveStatus(for: rule, now: now)
        return Button {
            if RulePolicy.canUnblock(dto, usage: enforcer.usage(for: dto, at: now), at: now) {
                unblockCandidate = rule
            } else {
                hardModeBlockedAttempt = true
            }
        } label: {
            HStack {
                kindIcon(for: rule)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .foregroundStyle(Color.primary)
                    Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                if rule.hardMode {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Unblock")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityIdentifier("blockedTile-\(rule.name)")
    }

    /// The rule's kind icon, tinted, sized to align row text. Decorative — the
    /// type is also spelled out in the subtitle, so it is hidden from VoiceOver.
    private func kindIcon(for rule: BlockingRule) -> some View {
        Image(systemName: rule.kind.symbolName)
            .foregroundStyle(.tint)
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    // MARK: - Usage

    /// Live tracking for every limit rule scheduled today that is *not* already
    /// blocking. Once a budget is spent (the rule is actively blocking) the row
    /// moves up to "Currently Blocking"; a soft-unblocked rule (paused) stays
    /// here reading "Paused".
    @ViewBuilder
    private func usageSection(now: Date) -> some View {
        let tracked = rules.filter {
            $0.kind != .schedule && $0.isEnabled && $0.dto.isScheduledToday(at: now)
                && !liveStatus(for: $0, now: now).isActive
        }
        if !tracked.isEmpty {
            Section {
                ForEach(tracked) { rule in
                    usageRow(for: rule, now: now)
                }
            } header: {
                Text("Usage").textCase(nil)
            }
        }
    }

    private func usageRow(for rule: BlockingRule, now: Date) -> some View {
        let dto = rule.dto
        let usage = enforcer.usage(for: dto, at: now) ?? RuleUsage()
        let status = liveStatus(for: rule, now: now)
        return HStack {
            kindIcon(for: rule)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .foregroundStyle(Color.primary)
                Text(UsageDisplay.homeSubtitle(for: dto, status: status, usage: usage, relativeTo: now))
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("usageRow-\(rule.name)")
    }
}
