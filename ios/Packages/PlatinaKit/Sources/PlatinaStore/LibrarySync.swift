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
    @ObservationIgnored public var onError: ((PSNError) -> Void)?
    /// Trophies a sync found earned since the store last saw them (not on a first fill): the
    /// background refresh tells the person about them.
    @ObservationIgnored public var onNewTrophies: (([TrophyRecord]) -> Void)?
    /// After every finished sync: the widgets' snapshot follows.
    @ObservationIgnored public var onSynced: (() -> Void)?

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
            var newlyEarned: [TrophyRecord] = []
            for (index, item) in plan.items.enumerated() {
                newlyEarned += try await fetchTrophies(of: item.title, groups: item.fetchesGroups)
                status = .syncing(done: index + 1, total: plan.items.count)
            }
            if !newlyEarned.isEmpty {
                onNewTrophies?(newlyEarned)
            }
            pendingGames = plan.deferred

            try await syncPlayTime()

            let finished = now()
            try store.markSynced(at: finished)
            lastSyncedAt = finished
            status = .idle
            onSynced?()
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

    /// Asks PSN whether a game changed and brings the change: one request when nothing did, two
    /// when trophies were earned (a session asks this every couple of minutes). A patch that
    /// added trophies fetches them all. Returns the trophies earned since the last look.
    public func checkGame(_ gameId: String) async throws -> [TrophyRecord] {
        guard let game = try store.game(gameId) else { return [] }
        let title = game.title
        do {
            let progress = try await client.progress(for: title)
            if progress.trophySetVersion != game.trophySetVersion || game.trophies.isEmpty {
                let before = Set(game.trophies.filter(\.isEarned).map(\.trophyId))
                let updated = TrophyTitle(
                    npCommunicationId: title.npCommunicationId, npServiceName: title.npServiceName,
                    trophySetVersion: progress.trophySetVersion, trophyTitleName: title.trophyTitleName,
                    trophyTitleIconUrl: title.trophyTitleIconUrl, trophyTitlePlatform: title.trophyTitlePlatform,
                    hasTrophyGroups: title.hasTrophyGroups, definedTrophies: title.definedTrophies,
                    earnedTrophies: progress.earnedTrophies, progress: progress.progress,
                    lastUpdatedDateTime: progress.lastUpdatedDateTime
                )
                try await fetchTrophies(of: updated, groups: title.hasTrophyGroups)
                return (try store.game(gameId)?.trophies ?? []).filter { $0.isEarned && !before.contains($0.trophyId) }
            }
            guard progress.lastUpdatedDateTime != game.lastUpdated || progress.earnedTrophies != game.earned else {
                return []
            }
            let earnings = try await client.earnings(for: title)
            return try store.save(progress: progress, earnings: earnings, for: gameId)
        } catch {
            fail(error)
            throw error
        }
    }

    /// The time played, now: at the start and the end of a session.
    public func refreshPlayTime() async {
        do {
            try await syncPlayTime()
        } catch {
            fail(error)
        }
    }

    @ObservationIgnored private var presenceCheckedAt: Date?
    @ObservationIgnored private var presenceGameId: String?

    /// The stored game running on the console now, if any. PSN is asked at most every three
    /// minutes; the answer is kept in between.
    public func runningGame(force: Bool = false) async -> String? {
        if !force, let checked = presenceCheckedAt, now().timeIntervalSince(checked) < 180 {
            return presenceGameId
        }
        presenceCheckedAt = now()
        guard let presence = try? await client.presence(), let running = presence.runningGame else {
            presenceGameId = nil
            return nil
        }
        var links = (try? store.titleLinks()) ?? [:]
        if links[running.npTitleId] == nil {
            if let answer = try? await client.trophyLinks(forTitleIds: [running.npTitleId]) {
                try? store.save(links: answer, asked: [running.npTitleId], at: now())
                links = (try? store.titleLinks()) ?? links
            }
        }
        let gameId = links[running.npTitleId]?.first { (try? store.game($0)) != nil }
        presenceGameId = gameId
        return gameId
    }

    @discardableResult
    private func fetchTrophies(of title: TrophyTitle, groups fetchesGroups: Bool) async throws -> [TrophyRecord] {
        async let trophiesRequest = client.trophies(for: title)
        var groups: [TrophyGroup]?
        if fetchesGroups {
            groups = try await client.trophyGroups(for: title)
        }
        let trophies = try await trophiesRequest
        return try store.save(trophies: trophies, groups: groups, for: title)
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
