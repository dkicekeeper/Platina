import Foundation
import PSNKit

/// What the store remembers about the last time a game's trophies were fetched.
public struct DetailState: Sendable, Hashable {
    /// The game's `lastUpdatedDateTime` when its trophies were fetched.
    public let lastUpdated: Date?
    /// Its `trophySetVersion` then: a patch that adds trophies changes it.
    public let trophySetVersion: String?
    /// Whether its groups (base game, DLC) are stored.
    public let hasGroups: Bool

    public init(lastUpdated: Date?, trophySetVersion: String?, hasGroups: Bool) {
        self.lastUpdated = lastUpdated
        self.trophySetVersion = trophySetVersion
        self.hasGroups = hasGroups
    }
}

/// One sync's share of trophy fetching. Sony limits requests without saying how much, so a sync
/// fetches at most `requestBudget` requests' worth of games; the rest wait for the next one
/// (the first sync of a big library takes a few). docs/PLAN.md §6.
public struct SyncPlan: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let title: TrophyTitle
        /// The groups are fetched too (one more request).
        public let fetchesGroups: Bool

        public var requestCount: Int { fetchesGroups ? 3 : 2 }
    }

    /// The games whose trophies this sync fetches, the most recently changed first.
    public let items: [Item]
    /// Games that also need it but wait for the next sync.
    public let deferred: Int

    public var requestCount: Int { items.reduce(0) { $0 + $1.requestCount } }
}

public enum SyncPlanner {
    /// Requests one sync may spend on trophies (two or three per game).
    public static let defaultRequestBudget = 60

    /// Whether a game's stored trophies are behind what PSN says about it.
    public static func needsDetails(_ title: TrophyTitle, stored: DetailState?) -> Bool {
        guard let stored else { return true }
        return stored.lastUpdated != title.lastUpdatedDateTime
            || stored.trophySetVersion != title.trophySetVersion
            || (title.hasTrophyGroups && !stored.hasGroups)
    }

    /// The games to fetch trophies for in this sync.
    /// - Parameter priority: a game the person is looking at goes first whatever its date.
    public static func plan(
        titles: [TrophyTitle],
        stored: [String: DetailState],
        requestBudget: Int = defaultRequestBudget,
        priority: String? = nil
    ) -> SyncPlan {
        let stale = titles
            .filter { needsDetails($0, stored: stored[$0.id]) }
            .sorted { lhs, rhs in
                if lhs.id == priority { return true }
                if rhs.id == priority { return false }
                return lhs.lastUpdatedDateTime > rhs.lastUpdatedDateTime
            }
        var items: [SyncPlan.Item] = []
        var spent = 0
        for title in stale {
            let item = SyncPlan.Item(
                title: title,
                fetchesGroups: title.hasTrophyGroups && !(stored[title.id]?.hasGroups ?? false)
            )
            // The first game always goes, even over the budget: a sync that fetches nothing
            // would never finish the library.
            guard items.isEmpty || spent + item.requestCount <= requestBudget else { break }
            items.append(item)
            spent += item.requestCount
        }
        return SyncPlan(items: items, deferred: stale.count - items.count)
    }
}
