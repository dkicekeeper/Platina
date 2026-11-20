import Foundation
import Observation
import PSNKit

/// A game's screen: its trophy groups and every trophy with the person's progress.
@MainActor
@Observable
final class GameModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, notEarned, earned
        var id: String { rawValue }
    }

    let title: TrophyTitle
    private(set) var state: State = .loading
    private(set) var groups: [TrophyGroup] = []
    private(set) var trophies: [Trophy] = []
    var filter: Filter = .notEarned

    private let client: PSNClient
    private let onError: (any Error) -> Void

    init(title: TrophyTitle, client: PSNClient, onError: @escaping (any Error) -> Void) {
        self.title = title
        self.client = client
        self.onError = onError
    }

    func load() async {
        if trophies.isEmpty { state = .loading }
        do {
            async let loadedTrophies = client.trophies(for: title)
            // Groups only name the DLC sections: without them the list still shows.
            if title.hasTrophyGroups, groups.isEmpty {
                groups = (try? await client.trophyGroups(for: title)) ?? []
            }
            trophies = try await loadedTrophies
            state = .loaded
        } catch {
            onError(error)
            if trophies.isEmpty {
                state = .failed(error.userMessage)
            }
        }
    }

    /// The trophies under the filter, by group (base game first), each group platinum first,
    /// then by rarity (the rarest last: what is left is usually the hard part).
    var sections: [TrophySection] {
        let visible = trophies.filter { trophy in
            switch filter {
            case .all: true
            case .notEarned: !trophy.isEarned
            case .earned: trophy.isEarned
            }
        }
        let byGroup = Dictionary(grouping: visible, by: \.groupId)
        let groupOrder = groups.isEmpty ? byGroup.keys.sorted() : groups.map(\.trophyGroupId)
        return groupOrder.compactMap { id in
            guard let items = byGroup[id], !items.isEmpty else { return nil }
            let sorted = items.sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type < rhs.type }
                return (lhs.earnedRate ?? 100) > (rhs.earnedRate ?? 100)
            }
            return TrophySection(id: id, group: groups.first { $0.trophyGroupId == id }, trophies: sorted)
        }
    }

    var earnedCount: Int { trophies.filter(\.isEarned).count }
}

/// The trophies of one group (the base game or a DLC) under the current filter.
struct TrophySection: Identifiable {
    let id: String
    let group: TrophyGroup?
    let trophies: [Trophy]
}
