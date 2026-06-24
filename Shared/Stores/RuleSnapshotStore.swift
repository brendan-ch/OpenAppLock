//
//  RuleSnapshotStore.swift
//  OpenAppLock
//

import Foundation

/// Persistence for the rule mirror in the shared app-group defaults. Stores
/// `RuleSnapshotDTO`s written by the app and read back by the Screen Time
/// extensions.
final class RuleSnapshotStore {
    private static let key = "ruleSnapshots"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    func save(_ snapshots: [RuleSnapshotDTO]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func load() -> [RuleSnapshotDTO] {
        guard let data = defaults.data(forKey: Self.key),
              let snapshots = try? JSONDecoder().decode([RuleSnapshotDTO].self, from: data)
        else { return [] }
        return snapshots
    }

    func snapshot(for ruleID: UUID) -> RuleSnapshotDTO? {
        load().first { $0.id == ruleID }
    }
}
