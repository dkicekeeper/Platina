#if canImport(SwiftData)
import Foundation
import Observation
import PSNKit
import PlatinaCore

/// Fills the store from PSN, sparing Sony's limits (docs/PLAN.md §6):
/// - the trophy lists, the level and the profile every sync (three requests);
/// - trophies only for games that changed, newest first, `requestBudget` requests a sync; a big
///   library's first fill takes a few syncs;
/// - the time played, asking each game title's trophy lists once.
/// A sync runs on launch, on return to the app and on pull to refresh; on its own no more often
/// than every `minimumInterval`, unless games are still waiting for their trophies.
@MainActor
@Observable
public final class LibrarySync {
    public enum Status: Equatable, Sendable {
        case idle
        /// `done` of `total` games' trophies fetched in this sync (0 of 0 while reading the list).
        case syncing(done: Int, total: Int)
        case failed(PSNError)
    }

    public private(set) var status: Status = .idle
    /// Games whose trophies wait for the next sync.
    public private(set) var pendingGames = 0
    public private(set) var lastSyncedAt: Date?

    /// Session errors go here, for the app to sign out.
    public var onError: ((PSNError) -> Void)?

    public var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    private let client: PSNClient
    private let store: LibraryStore
    private let requestBudget: Int
    private let minimumInterval: TimeInterval
    private let now: () -> Date

    public init(
        client: PSNClient,
        store: LibraryStore,
        requestBudget: Int = SyncPlanner.defaultRequestBudget,
        minimumInterval: TimeInterval = 10 * 60,
        now: @escaping () -> Date = { Date() }
    ) {
        self.client = client
        self.store = store
        self.requestBudget = requestBudget
        self.minimumInterval = minimumInterval
        self.now = now
        lastSyncedAt = try? store.profile()?.lastSyncedAt
    }

    /// Syncs the library.
    /// - Parameters:
    ///   - force: pull to refresh: whatever the time since the last sync.
    ///   - priority: a game on screen fetches its trophies first.
    public func sync(force: Bool = false, priority: String? = nil) async {
        guard !isSyncing else { return }
        if !force, pendingGames == 0, let lastSyncedAt, now().timeIntervalSince(lastSyncedAt) < minimumInterval {
            return
        }
        status = .syncing(done: 0, total: 0)
        do {
            async let summaryRequest = client.trophySummary()
            async let titlesRequest = client.trophyTitles()
            let summary = try await summaryRequest
            let titles = try await titlesRequest.filter(\.isPS5)
            let profile = try? await client.profile()
            try store.save(summary: summary, profile: profile, syncedAt: nil)
            try store.save(titles: titles)

            let plan = SyncPlanner.plan(
                titles: titles, stored: try store.detailStates(), requestBudget: requestBudget, priority: priority
            )
            status = .syncing(done: 0, total: plan.items.count)
            for (index, item) in plan.items.enumerated() {
                try await fetchTrophies(of: item.title, groups: item.fetchesGroups)
                status = .syncing(done: index + 1, total: plan.items.count)
            }
            pendingGames = plan.deferred

            try await syncPlayTime()

            let finished = now()
            try store.markSynced(at: finished)
            lastSyncedAt = finished
            status = .idle
        } catch {
            fail(error)
        }
    }

    /// The trophies of one game now, when its screen opens and they are missing or behind.
    public func refreshGame(_ gameId: String) async {
        guard let game = try? store.game(gameId), !game.hasCurrentDetails else { return }
        let title = game.title
        let fetchesGroups = title.hasTrophyGroups && game.groups.isEmpty
        do {
            try await fetchTrophies(of: title, groups: fetchesGroups)
        } catch {
            fail(error)
        }
    }

    private func fetchTrophies(of title: TrophyTitle, groups fetchesGroups: Bool) async throws {
        async let trophiesRequest = client.trophies(for: title)
        var groups: [TrophyGroup]?
        if fetchesGroups {
            groups = try await client.trophyGroups(for: title)
        }
        let trophies = try await trophiesRequest
        try store.save(trophies: trophies, groups: groups, for: title)
    }

    /// The time played. Only a session or rate-limit error stops the sync: without the game
    /// list the library is still whole.
    private func syncPlayTime() async throws {
        do {
            let played = try await client.playedGames()
            let ps5 = played.filter { $0.category == nil || $0.category == "ps5_native_game" }
            let unlinked = PlayTimeLinker.unlinkedTitleIds(played: ps5, known: try store.knownTitleIds(), limit: 25)
            if !unlinked.isEmpty {
                let links = try await client.trophyLinks(forTitleIds: unlinked)
                try store.save(links: links, asked: unlinked, at: now())
            }
            try store.save(playTime: PlayTimeLinker.playTime(played: played, links: try store.titleLinks()))
        } catch let error as PSNError {
            switch error {
            case .sessionExpired, .notSignedIn, .rateLimited: throw error
            default: return
            }
        }
    }

    private func fail(_ error: any Error) {
        let psnError = (error as? PSNError) ?? .decoding(String(describing: error))
        status = .failed(psnError)
        onError?(psnError)
    }
}
#endif
