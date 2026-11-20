#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import PSNKit
import PlatinaCore
@testable import PlatinaStore

/// PSN as the fixtures describe it: two PS5 games and a PS4 one, one game played.
final class FakePSN: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    var refreshFails = false

    var requestedPaths: [String] { lock.withLock { paths } }

    func resetLog() {
        lock.withLock { paths.removeAll() }
    }

    func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let offset = query.first { $0.name == "offset" }?.value
        let (failsRefresh, isExpired) = lock.withLock { () -> (Bool, Bool) in
            paths.append(path)
            return (refreshFails, refreshFails && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer") == true)
        }

        let status: Int
        let body: Data
        switch true {
        case path.hasSuffix("/oauth/token"):
            if failsRefresh {
                (status, body) = (400, Data(#"{"error":"invalid_grant"}"#.utf8))
            } else {
                (status, body) = (200, Data(#"{"access_token":"a2","expires_in":3600,"refresh_token":"r2","refresh_token_expires_in":5183999}"#.utf8))
            }
        case isExpired:
            (status, body) = (401, Data())
        case path.hasSuffix("/trophySummary"):
            (status, body) = (200, try fixture("trophySummary"))
        case path.hasSuffix("/profiles"):
            (status, body) = (200, try fixture("profile"))
        case path.hasSuffix("/users/me/trophyTitles"):
            (status, body) = (200, try fixture(offset == "0" ? "trophyTitles-page1" : "trophyTitles-page2"))
        case path.hasSuffix("/trophyGroups"):
            (status, body) = (200, try fixture("trophyGroups"))
        case path.contains("/users/me/npCommunicationIds/"):
            (status, body) = (200, try fixture("earnedTrophies"))
        case path.contains("/npCommunicationIds/"):
            (status, body) = (200, try fixture("titleTrophies"))
        case path.hasSuffix("/titles/trophyTitles"):
            (status, body) = (200, try fixture("trophyLinks"))
        case path.contains("/gamelist/"):
            (status, body) = (200, try fixture("playedGames"))
        default:
            (status, body) = (404, Data())
        }
        return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

private let validTokens = PSNTokens(
    accessToken: "a1",
    accessTokenExpiresAt: Date().addingTimeInterval(3600),
    refreshToken: "r1",
    refreshTokenExpiresAt: Date().addingTimeInterval(86_400)
)

@MainActor
private func makeSync(budget: Int = 60) throws -> (LibrarySync, LibraryStore, FakePSN) {
    let store = LibraryStore(container: try LibraryStore.makeContainer(inMemory: true))
    let psn = FakePSN()
    let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: psn, language: "ru-RU")
    let sync = LibrarySync(client: client, store: store, requestBudget: budget, minimumInterval: 600)
    return (sync, store, psn)
}

private func isTrophyRequest(_ path: String) -> Bool {
    path.contains("/npCommunicationIds/")
}

@MainActor
@Suite("Store and sync")
struct StoreTests {
    @Test("A first sync fills games, trophies, groups, time and the profile")
    func firstSync() async throws {
        let (sync, store, _) = try makeSync()
        await sync.sync()

        #expect(sync.status == .idle)
        #expect(sync.lastSyncedAt != nil)
        #expect(sync.pendingGames == 0)

        let games = try store.games()
        #expect(Set(games.map(\.id)) == ["NPWR28536_00", "NPWR20188_00"])

        let lamb = try #require(try store.game("NPWR28536_00"))
        #expect(lamb.trophies.count == 3)
        #expect(lamb.groups.count == 2)
        #expect(lamb.hasCurrentDetails)
        #expect(lamb.playSeconds == 137_525)
        #expect(lamb.playCount == 41)
        #expect(lamb.coverURLString?.hasSuffix("cotl-ru.png") == true)
        #expect(lamb.trophies.first { $0.trophyId == 12 }?.progress?.current == 3)

        let profile = try #require(try store.profile())
        #expect(profile.level == 412)
        #expect(profile.onlineId == "trophy_hunter")

        #expect(try store.earnedTrophies().count == 2)
    }

    @Test("A sync with nothing changed fetches no trophies and asks no title twice")
    func quietSync() async throws {
        let (sync, _, psn) = try makeSync()
        await sync.sync()
        psn.resetLog()

        await sync.sync(force: true)
        #expect(sync.status == .idle)
        #expect(!psn.requestedPaths.contains(where: isTrophyRequest))
        #expect(!psn.requestedPaths.contains { $0.hasSuffix("/titles/trophyTitles") })
    }

    @Test("Without force, a recent sync is not repeated")
    func throttled() async throws {
        let (sync, _, psn) = try makeSync()
        await sync.sync()
        psn.resetLog()
        await sync.sync()
        #expect(psn.requestedPaths.isEmpty)
    }

    @Test("A small budget leaves games for the next sync, which takes them even without force")
    func budget() async throws {
        let (sync, store, psn) = try makeSync(budget: 2)
        await sync.sync()
        #expect(sync.pendingGames == 1)
        let fetched = try store.games().filter(\.hasCurrentDetails).map(\.id)
        #expect(fetched == ["NPWR28536_00"])

        psn.resetLog()
        await sync.sync()
        #expect(sync.pendingGames == 0)
        #expect(try store.games().allSatisfy(\.hasCurrentDetails))
    }

    @Test("A dead session fails the sync and reports it")
    func sessionExpired() async throws {
        let (sync, _, psn) = try makeSync()
        psn.refreshFails = true
        var reported: PSNError?
        sync.onError = { reported = $0 }
        await sync.sync()
        #expect(sync.status == .failed(.sessionExpired))
        #expect(reported == .sessionExpired)
    }

    @Test("A game PSN no longer lists leaves the store with its trophies")
    func hiddenGame() async throws {
        let (sync, store, _) = try makeSync()
        await sync.sync()
        let remaining = try #require(try store.game("NPWR20188_00")).title
        try store.save(titles: [remaining])
        #expect(try store.games().map(\.id) == ["NPWR20188_00"])
        let orphans = try store.context.fetch(FetchDescriptor<TrophyRecord>(predicate: #Predicate { $0.gameId == "NPWR28536_00" }))
        #expect(orphans.isEmpty)
    }

    @Test("Plans live in the person's own store and survive erasing the cache")
    func plans() async throws {
        let (sync, store, _) = try makeSync()
        await sync.sync()
        try store.setPlan(.chasing, for: "NPWR28536_00")
        try store.setPlan(.later, for: "NPWR28536_00")
        #expect(try store.plans() == ["NPWR28536_00": .later])

        try store.eraseCache()
        #expect(try store.games().isEmpty)
        #expect(try store.profile() == nil)
        #expect(try store.plans() == ["NPWR28536_00": .later])
    }

    @Test("Opening a game fetches its trophies when they are behind")
    func refreshGame() async throws {
        let (sync, store, psn) = try makeSync(budget: 2)
        await sync.sync()
        let astro = try #require(try store.game("NPWR20188_00"))
        #expect(!astro.hasCurrentDetails)

        psn.resetLog()
        await sync.refreshGame("NPWR20188_00")
        #expect(astro.hasCurrentDetails)
        #expect(psn.requestedPaths.filter(isTrophyRequest).count == 2)

        psn.resetLog()
        await sync.refreshGame("NPWR20188_00")
        #expect(psn.requestedPaths.isEmpty)
    }
}
#endif
