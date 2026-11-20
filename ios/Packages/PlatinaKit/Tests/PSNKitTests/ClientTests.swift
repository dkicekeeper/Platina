import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PSNKit

@Suite("Client")
struct ClientTests {
    @Test("Every page of trophy lists, with the token and the language")
    func paging() async throws {
        let transport = MockTransport { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "ru-RU")
            #expect(request.url?.path == "/api/trophy/v1/users/me/trophyTitles")
            return try Fixture.reply(request.queryItems["offset"] == "0" ? "trophyTitles-page1" : "trophyTitles-page2")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let titles = try await client.trophyTitles()
        #expect(titles.map(\.id) == ["NPWR28536_00", "NPWR10600_00", "NPWR20188_00"])
        #expect(transport.requests.map { $0.queryItems["offset"] } == ["0", "2"])
    }

    @Test("A game's trophies ask with its service name")
    func trophies() async throws {
        let transport = MockTransport { request in
            #expect(request.queryItems["npServiceName"] == "trophy2")
            let path = request.url?.path ?? ""
            return try Fixture.reply(path.contains("/users/me/") ? "earnedTrophies" : "titleTrophies")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let page = try JSONDecoder.psn.decode(TrophyTitlesPage.self, from: Fixture.data("trophyTitles-page1"))
        let trophies = try await client.trophies(for: page.trophyTitles[0])
        #expect(trophies.count == 3)
        #expect(trophies.filter(\.isEarned).count == 1)
        #expect(transport.requestCount == 2)
    }

    @Test("An access token about to run out is refreshed first")
    func refreshBeforeRequest() async throws {
        var expiring = validTokens
        expiring.accessTokenExpiresAt = fixedNow.addingTimeInterval(30)
        let store = InMemoryTokenStore(expiring)
        let transport = MockTransport { request in
            if request.url?.path == "/api/authz/v3/oauth/token" {
                #expect(request.formFields["refresh_token"] == "refresh-1")
                #expect(request.formFields["grant_type"] == "refresh_token")
                return tokenResponse(access: "access-2", refresh: "refresh-2")
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2")
            return try Fixture.reply("trophySummary")
        }
        let client = PSNClient(store: store, transport: transport, language: "en-US", now: { fixedNow })
        let summary = try await client.trophySummary()
        #expect(summary.level == 412)
        #expect(try store.load()?.refreshToken == "refresh-2")
    }

    @Test("A 401 refreshes once and repeats the request")
    func refreshOnUnauthorized() async throws {
        let transport = MockTransport { request in
            if request.url?.path == "/api/authz/v3/oauth/token" {
                return tokenResponse(access: "access-2", refresh: "refresh-2")
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" {
                return .init(status: 401, body: Data(#"{"error":{"code":2241801,"message":"Access token required"}}"#.utf8))
            }
            return try Fixture.reply("profile")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let profile = try await client.profile()
        #expect(profile.onlineId == "trophy_hunter")
        #expect(transport.requestCount == 3)
    }

    @Test("A dead refresh token signs out")
    func sessionExpired() async throws {
        let store = InMemoryTokenStore(validTokens)
        let transport = MockTransport { request in
            if request.url?.path == "/api/authz/v3/oauth/token" {
                return .init(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            return .init(status: 401)
        }
        let client = PSNClient(store: store, transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.sessionExpired) {
            _ = try await client.trophySummary()
        }
        #expect(await !client.isSignedIn)
        #expect(try store.load() == nil)
    }

    @Test("Concurrent requests share one refresh")
    func singleRefresh() async throws {
        var expiring = validTokens
        expiring.accessTokenExpiresAt = fixedNow
        let transport = MockTransport { request in
            if request.url?.path == "/api/authz/v3/oauth/token" {
                return tokenResponse(access: "access-2", refresh: "refresh-2")
            }
            return try Fixture.reply("trophySummary")
        }
        let client = PSNClient(store: InMemoryTokenStore(expiring), transport: transport, language: "ru-RU", now: { fixedNow })
        async let first = client.trophySummary()
        async let second = client.trophySummary()
        async let third = client.trophySummary()
        _ = try await (first, second, third)
        let refreshes = transport.requests.filter { $0.url?.path == "/api/authz/v3/oauth/token" }
        #expect(refreshes.count == 1)
    }

    @Test("PSN's errors keep their code and message")
    func httpError() async {
        let transport = MockTransport { _ in
            .init(status: 403, body: Data(#"{"error":{"referenceId":"x","code":2240526,"message":"Not permitted by access control"}}"#.utf8))
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.http(status: 403, code: 2240526, message: "Not permitted by access control")) {
            _ = try await client.presence()
        }
    }

    @Test("Too many requests")
    func rateLimited() async {
        let transport = MockTransport { _ in .init(status: 429, headers: ["Retry-After": "120"]) }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.rateLimited(retryAfter: 120)) {
            _ = try await client.playedGames()
        }
    }

    @Test("Signed out, nothing is sent")
    func notSignedIn() async {
        let transport = MockTransport { _ in .init() }
        let client = PSNClient(store: InMemoryTokenStore(), transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.notSignedIn) {
            _ = try await client.trophySummary()
        }
        #expect(transport.requestCount == 0)
    }

    @Test("Title ids are asked five at a time")
    func trophyLinks() async throws {
        let transport = MockTransport { _ in try Fixture.reply("trophyLinks") }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let ids = (1...7).map { String(format: "PPSA%05d_00", $0) }
        _ = try await client.trophyLinks(forTitleIds: ids)
        #expect(transport.requests.map { $0.queryItems["npTitleIds"]?.split(separator: ",").count } == [5, 2])
    }
}
