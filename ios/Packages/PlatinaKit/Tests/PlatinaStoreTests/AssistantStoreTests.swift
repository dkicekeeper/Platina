#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import PSNKit
import PlatinaCore
import PlatinaAssistant
@testable import PlatinaStore

/// Plati's server as a script: one entry per model call.
final class ScriptedAssistant: AssistantTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [[AssistantStreamEvent]]
    private(set) var requests: [AssistantTurnRequest] = []

    init(_ script: [[AssistantStreamEvent]]) {
        self.script = script
    }

    var turns: [AssistantTurnRequest] { lock.withLock { requests } }

    func turn(_ request: AssistantTurnRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let events = lock.withLock { () -> [AssistantStreamEvent] in
            requests.append(request)
            return script.isEmpty ? [] : script.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func guide(_ request: GuideRequest) -> AsyncThrowingStream<GuideStreamEvent, Error> {
        let guide = Guide(
            gameId: request.game.npCommunicationId, language: request.language, generatedAt: nil,
            summary: .init(difficulty: 4, hoursMin: 10, hoursMax: 15, playthroughs: 1, onlineTrophies: 0,
                           missableTrophies: 1, glitchedTrophies: 0, difficultyAffects: false, overview: "Лёгкая."),
            steps: [.init(title: "Сюжет", text: "Пройдите сюжет.", trophyIds: [0, 12])],
            missable: [.init(trophyId: 12, note: "До финала")],
            tips: [.init(trophyId: 12, text: "Играйте в кости.", sourceIds: ["s1"])],
            sources: [.init(id: "s1", title: "Stratege.ru", url: "https://stratege.ru")],
            stratege: nil
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(step: "stratege"))
            continuation.yield(.guide(guide))
            continuation.finish()
        }
    }

    func cachedGuide(gameId: String, language: String) async throws -> Guide? { nil }
}

private func toolCall(_ name: String, _ input: JSONValue, id: String = "t1") -> AssistantStreamEvent {
    .done(AssistantTurnDone(content: [["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]], stopReason: "tool_use"))
}

private func answer(_ text: String) -> AssistantStreamEvent {
    .done(AssistantTurnDone(content: [["type": "text", "text": .string(text)]], stopReason: "end_turn"))
}

@MainActor
private func makeAssistant(_ script: [[AssistantStreamEvent]]) async throws -> (AssistantService, LibraryStore, SessionTracker, ScriptedAssistant) {
    let store = LibraryStore(container: try LibraryStore.makeContainer(inMemory: true))
    let psn = FakePSN()
    let tokens = PSNTokens(accessToken: "a1", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r1", refreshTokenExpiresAt: Date().addingTimeInterval(86_400))
    let client = PSNClient(store: InMemoryTokenStore(tokens), transport: psn, language: "ru-RU")
    let sync = LibrarySync(client: client, store: store)
    await sync.sync()
    let sessions = SessionTracker(store: store, sync: sync)
    let server = ScriptedAssistant(script)
    let assistant = AssistantService(store: store, sessions: sessions, transport: server, language: "ru")
    return (assistant, store, sessions, server)
}

@MainActor
@Suite("Plati on the phone")
struct AssistantStoreTests {
    @Test("Tools read the library and keep hidden trophies hidden")
    func reading() async throws {
        let (assistant, store, sessions, _) = try await makeAssistant([])
        let toolkit = AssistantToolkit(store: store, sessions: sessions, guides: assistant.guides)

        let game = await toolkit.execute(name: "get_game", input: ["game_id": "NPWR28536_00"])
        #expect(game.value?.value(atPath: "game.progress_percent")?.numberValue == 64)
        #expect(game.value?.value(atPath: "groups")?.arrayValue?.count == 2)

        let trophies = await toolkit.execute(name: "list_trophies", input: ["game_id": "NPWR28536_00", "filter": "all"])
        let list = try #require(trophies.value?.arrayValue)
        let hidden = try #require(list.first { $0["id"]?.numberValue == 40 })
        // Earned, so no longer a secret.
        #expect(hidden["name"]?.stringValue == "Шерстополь")
        #expect(hidden["hidden"]?.boolValue == true)

        let games = await toolkit.execute(name: "list_games", input: ["filter": "all"])
        #expect(games.value?.arrayValue?.count == 2)

        let unknown = await toolkit.execute(name: "get_game", input: ["game_id": "NOPE"])
        #expect(unknown.error != nil)
    }

    @Test("A turn's answer is kept, and the thread comes back after a relaunch")
    func threadPersists() async throws {
        let (assistant, store, sessions, server) = try await makeAssistant([
            [toolCall("list_trophies", ["game_id": "NPWR28536_00"]), ],
            [.text("Осталась «Улыбка фортуны»."), answer("Осталась «Улыбка фортуны».")],
        ])
        let thread = assistant.thread(gameId: "NPWR28536_00")
        await thread.send("Что осталось?")
        #expect(thread.failure == nil)
        #expect(thread.messages.map(\.role) == [.user, .assistant])
        #expect(thread.messages.last?.text == "Осталась «Улыбка фортуны».")
        let firstTurn = try #require(server.turns.first)
        #expect(firstTurn.messages.first?.text.contains("<app_context>") == true)
        #expect(firstTurn.messages.first?.text.contains("open_game: NPWR28536_00") == true)

        let reopened = AssistantService(store: store, sessions: sessions, transport: server, language: "ru")
        let again = reopened.thread(gameId: "NPWR28536_00")
        #expect(again.messages.map(\.text) == thread.messages.map(\.text))
    }

    @Test("A failed turn shows its failure and can be retried")
    func failure() async throws {
        let (assistant, _, _, _) = try await makeAssistant([
            [.error(code: "quota", retryable: false)],
            [answer("Привет!")],
        ])
        let thread = assistant.thread(gameId: nil)
        await thread.send("Привет")
        #expect(thread.failure == "quota")
        #expect(thread.messages.last?.failed == true)
        await thread.retry()
        #expect(thread.failure == nil)
        #expect(thread.messages.last?.text == "Привет!")
        #expect(thread.messages.first?.failed == false)
    }

    @Test("A session's plan: Plati sets the goals through the tool")
    func sessionPlan() async throws {
        let (assistant, _, sessions, _) = try await makeAssistant([
            [toolCall("set_session_goals", ["game_id": "NPWR28536_00", "trophy_ids": [12, 0, 999]])],
            [answer("Цели на сегодня: кости и платина.")],
        ])
        await sessions.start(gameId: "NPWR28536_00")
        let session = try #require(sessions.current)
        await assistant.planSession(session)
        #expect(session.goalTrophyIds == [12, 0])
        let thread = assistant.thread(gameId: "NPWR28536_00")
        #expect(thread.messages.first?.role == .event)
        #expect(thread.messages.last?.text == "Цели на сегодня: кости и платина.")
    }

    @Test("get_guide builds the guide once and keeps it")
    func guide() async throws {
        let (assistant, _, _, _) = try await makeAssistant([])
        #expect(assistant.guides.guide(for: "NPWR28536_00") == nil)
        let built = await assistant.guides.guideBuildingIfNeeded(gameId: "NPWR28536_00")
        #expect(built?.summary.difficulty == 4)
        #expect(assistant.guides.guide(for: "NPWR28536_00")?.tip(for: 12)?.text == "Играйте в кости.")
        #expect(assistant.guides.state(for: "NPWR28536_00") == .idle)
    }
}
#endif
