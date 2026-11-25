import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PSNKit

@Suite("Friends")
struct FriendsTests {
    @Test("Every page of the friends list")
    func friendIds() async throws {
        let transport = MockTransport { request in
            #expect(request.url?.path == "/api/userProfile/v1/internal/users/me/friends")
            return try Fixture.reply(request.queryItems["offset"] == "0" ? "friends-page1" : "friends-page2")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let ids = try await client.friendIds()
        #expect(ids == ["2984038888603282554", "8403439712302084350", "5512234401234567890"])
        #expect(transport.requests.map { $0.queryItems["offset"] } == ["0", "2"])
    }

    @Test("A friend's trophy lists read as the person's own")
    func friendTitles() async throws {
        let transport = MockTransport { request in
            #expect(request.url?.path == "/api/trophy/v1/users/2984038888603282554/trophyTitles")
            return try Fixture.reply(request.queryItems["offset"] == "0" ? "trophyTitles-page1" : "trophyTitles-page2")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let titles = try await client.trophyTitles(of: "2984038888603282554")
        #expect(titles?.map(\.id) == ["NPWR28536_00", "NPWR10600_00", "NPWR20188_00"])
    }

    @Test("A friend who hides trophies is nil, not an error")
    func hiddenTitles() async throws {
        let transport = MockTransport { _ in
            MockTransport.Reply(status: 403, body: try Fixture.data("hiddenTrophies"))
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let titles = try await client.trophyTitles(of: "8403439712302084350")
        #expect(titles == nil)
    }

    @Test("Another error is still an error")
    func otherErrors() async throws {
        let transport = MockTransport { _ in MockTransport.Reply(status: 500) }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.self) {
            _ = try await client.trophyTitles(of: "8403439712302084350")
        }
    }
}
