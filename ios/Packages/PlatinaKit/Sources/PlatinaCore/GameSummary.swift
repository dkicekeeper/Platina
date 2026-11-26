import Foundation
import PSNKit

/// What the person plans for a game, beyond what PSN knows. Kept on the device (and in iCloud
/// later, docs/architecture.md).
public enum GamePlanStatus: String, Codable, Sendable, CaseIterable {
    /// Nothing said: the game counts as in progress or not started by its trophies.
    case none
    /// Going for the platinum (and 100%).
    case chasing
    /// Put aside for now.
    case later
    /// Not going to finish it.
    case skip

    /// Shelved games leave "In progress" and "Not started" for the "Shelved" filter.
    public var isShelved: Bool { self == .later || self == .skip }
}

/// The library's filters (docs/domains/screens.md §3.2).
public enum GameShelf: String, CaseIterable, Sendable, Identifiable {
    case all, inProgress, platinum, completed, notStarted, shelved

    public var id: String { rawValue }
}

/// The library's orders.
public enum GameSort: String, CaseIterable, Sendable, Identifiable {
    /// The most recent trophy change first, as PSN lists them.
    case recent
    /// Closest to 100% first.
    case progress
    /// A to Z.
    case name
    /// The most time played first.
    case playTime

    public var id: String { rawValue }
}

/// A game as the library list sees it: a value the views build from the store, so filtering
/// and sorting stay testable without SwiftData.
public struct GameSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let progress: Int
    public let defined: TrophyCounts
    public let earned: TrophyCounts
    public let lastUpdated: Date
    public let playTime: TimeInterval?
    public let status: GamePlanStatus

    public init(
        id: String, name: String, progress: Int, defined: TrophyCounts, earned: TrophyCounts,
        lastUpdated: Date, playTime: TimeInterval?, status: GamePlanStatus
    ) {
        self.id = id
        self.name = name
        self.progress = progress
        self.defined = defined
        self.earned = earned
        self.lastUpdated = lastUpdated
        self.playTime = playTime
        self.status = status
    }

    public var hasPlatinum: Bool { defined.platinum > 0 }
    public var isPlatinumEarned: Bool { hasPlatinum && earned.platinum > 0 }
    public var isCompleted: Bool { defined.total > 0 && earned.total >= defined.total }
    public var isStarted: Bool { earned.total > 0 }

    public func belongs(to shelf: GameShelf) -> Bool {
        switch shelf {
        case .all: true
        case .platinum: isPlatinumEarned
        case .completed: isCompleted
        case .inProgress: isStarted && !isCompleted && !status.isShelved
        case .notStarted: !isStarted && !status.isShelved
        case .shelved: status.isShelved
        }
    }
}

public extension Array where Element == GameSummary {
    /// The games on a shelf whose name has `query` in it, in the given order.
    func filtered(shelf: GameShelf, query: String = "", sort: GameSort) -> [GameSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = filter { game in
            game.belongs(to: shelf) && (needle.isEmpty || game.name.localizedStandardContains(needle))
        }
        return matching.sorted { lhs, rhs in
            switch sort {
            case .recent:
                return lhs.lastUpdated > rhs.lastUpdated
            case .progress:
                if lhs.progress != rhs.progress { return lhs.progress > rhs.progress }
                return lhs.lastUpdated > rhs.lastUpdated
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            case .playTime:
                let left = lhs.playTime ?? -1
                let right = rhs.playTime ?? -1
                if left != right { return left > right }
                return lhs.lastUpdated > rhs.lastUpdated
            }
        }
    }

    /// How many games each shelf holds, for the chips' counts.
    func counts() -> [GameShelf: Int] {
        Dictionary(uniqueKeysWithValues: GameShelf.allCases.map { shelf in
            (shelf, filter { $0.belongs(to: shelf) }.count)
        })
    }
}
