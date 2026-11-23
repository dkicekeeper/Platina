import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PSNKit

/// Game Help, on the real answers from andshrew's API notes (the video tokens redacted there).
@Suite("Game Help")
struct GameHelpTests {
    private func object(_ text: String?) throws -> [String: Any] {
        let data = Data((text ?? "").utf8)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Which trophies have help: the app's persisted query, its client name, the list's id")
    func hints() async throws {
        let transport = MockTransport { request in
            #expect(request.url?.path == "/api/graphql/v1/op")
            #expect(request.queryItems["operationName"] == "metGetHintAvailability")
            #expect(request.value(forHTTPHeaderField: "apollographql-client-name") == "PlayStationApp-Android")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            return try Fixture.reply("gameHelpHints")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let hints = try await client.gameHelpHints(npCommunicationId: "NPWR20188_00")
        #expect(hints.map(\.trophyNumber) == [18, 21])
        #expect(hints.first?.udsObjectId == "GATCHA_SECRET")

        let request = try #require(transport.requests.first)
        #expect(try object(request.queryItems["variables"])["npCommId"] as? String == "NPWR20188_00")
        let persisted = try object(request.queryItems["extensions"])["persistedQuery"] as? [String: Any]
        #expect(persisted?["sha256Hash"] as? String == PSNClient.hintAvailabilityHash)
        #expect(persisted?["version"] as? Int == 1)
    }

    @Test("A trophy's help: its steps in order, the words trimmed, the video's stream")
    func tips() async throws {
        let transport = MockTransport { request in
            #expect(request.queryItems["operationName"] == "metGetTips")
            return try Fixture.reply("gameHelpTips")
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        let hint = GameHelpHint(trophyId: "21", udsObjectId: "Weapon_to_Level_5", helpType: "HINT")
        let help = try await client.gameHelp(npCommunicationId: "NPWR20842_00", hints: [hint])
        let trophy = try #require(help.first)
        #expect(trophy.trophyId == 21)
        #expect(trophy.tips.map(\.title) == ["HIGH FIVE", "INCREASED STATS"])
        #expect(trophy.tips.first?.text?.hasSuffix(" ") == false)
        #expect(trophy.tips.first?.videoURL?.host == "gms-ght.playstation-cloud.com")

        let variables = try object(transport.requests.first?.queryItems["variables"])
        let asked = variables["trophies"] as? [[String: String]]
        #expect(asked == [["trophyId": "21", "udsObjectId": "Weapon_to_Level_5", "helpType": "HINT"]])
    }

    @Test("No trophies, no request")
    func nothingToAsk() async throws {
        let transport = MockTransport { _ in .init(status: 500) }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        #expect(try await client.gameHelp(npCommunicationId: "NPWR20842_00", hints: []).isEmpty)
        #expect(transport.requestCount == 0)
    }

    @Test("A query Sony no longer knows is an error, not an empty answer")
    func unknownQuery() async throws {
        let transport = MockTransport { _ in
            .init(body: Data(#"{"errors":[{"message":"PersistedQueryNotFound"}],"data":null}"#.utf8))
        }
        let client = PSNClient(store: InMemoryTokenStore(validTokens), transport: transport, language: "ru-RU", now: { fixedNow })
        await #expect(throws: PSNError.decoding("GraphQL metGetHintAvailability: PersistedQueryNotFound")) {
            _ = try await client.gameHelpHints(npCommunicationId: "NPWR20188_00")
        }
    }
}
