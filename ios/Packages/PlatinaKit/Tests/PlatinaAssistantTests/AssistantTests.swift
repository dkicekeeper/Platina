import Foundation
import Testing
@testable import PlatinaAssistant

/// Answers turns from a script, one entry per model call.
final class ScriptedTransport: AssistantTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [[AssistantStreamEvent]]
    private(set) var requests: [AssistantTurnRequest] = []

    init(_ script: [[AssistantStreamEvent]]) {
        self.script = script
    }

    var requestCount: Int { lock.withLock { requests.count } }

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
        AsyncThrowingStream { $0.finish() }
    }

    func cachedGuide(gameId: String, language: String) async throws -> Guide? { nil }
}

@MainActor
final class RecordingToolkit: AssistantToolExecuting {
    var calls: [(String, JSONValue)] = []

    func execute(name: String, input: JSONValue) async -> AssistantToolOutput {
        calls.append((name, input))
        if name == "list_trophies" {
            return .success(["trophies": [["id": 12, "name": "Улыбка фортуны"]]])
        }
        return .failure("unknown tool \(name)")
    }
}

private func toolUseTurn(id: String, name: String, input: JSONValue) -> AssistantStreamEvent {
    .done(AssistantTurnDone(
        content: [
            ["type": "text", "text": "Сейчас посмотрю."],
            ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input],
        ],
        stopReason: "tool_use"
    ))
}

private func textTurn(_ text: String) -> AssistantStreamEvent {
    .done(AssistantTurnDone(content: [["type": "text", "text": .string(text)]], stopReason: "end_turn"))
}

@Suite("Wire")
struct WireTests {
    @Test("Server-sent events, with or without blank lines between them")
    func sse() {
        var parser = SSEParser()
        var events: [SSEParser.Event] = []
        for line in ["event: text", "data: {\"text\":\"При\"}", "event: tool", "data: {\"name\":\"list_trophies\"}", "", "event: done", "data: {\"content\":[],\"stop_reason\":\"end_turn\"}"] {
            if let event = parser.feed(line: line) { events.append(event) }
        }
        if let event = parser.finish() { events.append(event) }
        #expect(events.map(\.name) == ["text", "tool", "done"])
        #expect(AssistantStreamEvent(events[0]) == .text("При"))
        #expect(AssistantStreamEvent(events[1]) == .tool(name: "list_trophies"))
        #expect(AssistantStreamEvent(events[2]) == .done(AssistantTurnDone(content: [], stopReason: "end_turn")))
        #expect(AssistantStreamEvent(.init(name: "error", data: "{\"code\":\"quota\",\"retryable\":false}")) == .error(code: "quota", retryable: false))
        #expect(AssistantStreamEvent(.init(name: "search", data: "{\"query\":\"stratege cult of the lamb\"}")) == .search(query: "stratege cult of the lamb"))
    }

    @Test("A guide decodes, even without the lists")
    func guide() throws {
        let json = """
        {"gameId":"NPWR28536_00","language":"ru","summary":{"difficulty":4,"hoursMin":10,"hoursMax":15,"playthroughs":1,
        "onlineTrophies":0,"missableTrophies":1,"glitchedTrophies":0,"difficultyAffects":false,"overview":"Лёгкая платина."},
        "tips":[{"trophyId":12,"text":"Играйте в кости до финала.","sourceIds":["s1"]}],
        "sources":[{"id":"s1","title":"Stratege.ru","url":"https://stratege.ru"}]}
        """
        let guide = try JSONDecoder().decode(Guide.self, from: Data(json.utf8))
        #expect(guide.summary.difficulty == 4)
        #expect(guide.steps.isEmpty)
        #expect(guide.tip(for: 12)?.text == "Играйте в кости до финала.")
        #expect(guide.sources(of: try #require(guide.tip(for: 12))).map(\.url) == ["https://stratege.ru"])
        let event = GuideStreamEvent(.init(name: "guide", data: json.replacingOccurrences(of: "\n", with: "")))
        if case .guide(let streamed) = event {
            #expect(streamed.gameId == "NPWR28536_00")
        } else {
            Issue.record("not a guide event: \(String(describing: event))")
        }
    }

    @Test("The server's address from the build setting")
    func config() {
        #expect(AssistantConfig.url(host: "platina.example.workers.dev")?.absoluteString == "https://platina.example.workers.dev")
        #expect(AssistantConfig.url(host: "https://platina.example.workers.dev/")?.absoluteString == "https://platina.example.workers.dev")
        #expect(AssistantConfig.url(host: "") == nil)
        #expect(AssistantConfig.url(host: "$(PLATINA_ASSISTANT_HOST)") == nil)
        #expect(AssistantConfig.url(host: nil) == nil)
    }

    @Test("JSON values go back as they came")
    func jsonRoundTrip() throws {
        let value: JSONValue = ["type": "thinking", "signature": "abc", "n": 1.5, "list": [true, nil]]
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }
}

@MainActor
@Suite("Conversation")
struct ConversationTests {
    @Test("A tool call runs on the phone, its result goes back, the answer comes in text")
    func toolLoop() async throws {
        let transport = ScriptedTransport([
            [.text("Сейчас посмотрю."), .tool(name: "list_trophies"), toolUseTurn(id: "t1", name: "list_trophies", input: ["game_id": "NPWR28536_00"])],
            [.text("Тебе осталась "), .text("«Улыбка фортуны»."), textTurn("Тебе осталась «Улыбка фортуны».")],
        ])
        let toolkit = RecordingToolkit()
        let conversation = AssistantConversation(transport: transport, toolkit: toolkit, language: "ru")
        var progress: [AssistantConversation.Progress] = []
        let reply = try await conversation.send("Что осталось?", context: "<app_context>…</app_context>") { progress.append($0) }

        #expect(reply.text == "Тебе осталась «Улыбка фортуны».")
        #expect(reply.tools == ["list_trophies"])
        #expect(toolkit.calls.map(\.0) == ["list_trophies"])
        #expect(progress.contains(.tool("list_trophies")))
        #expect(progress.last == .text("Тебе осталась «Улыбка фортуны»."))

        // user (context + question), assistant (tool_use), user (tool_result), assistant (text)
        #expect(conversation.messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(conversation.messages[0].content.count == 2)
        let result = try #require(conversation.messages[2].content.first)
        #expect(result["type"] == "tool_result")
        #expect(result["tool_use_id"] == "t1")
        #expect(transport.requests.last?.language == "ru")
        #expect(transport.requests.last?.messages.count == 3)
    }

    @Test("A failed turn leaves no trace in the history")
    func rollback() async throws {
        let transport = ScriptedTransport([[.error(code: "quota", retryable: false)]])
        let conversation = AssistantConversation(transport: transport, toolkit: RecordingToolkit(), language: "ru")
        await #expect(throws: AssistantConversationError.stream(code: "quota", retryable: false)) {
            _ = try await conversation.send("Привет")
        }
        #expect(conversation.messages.isEmpty)
    }

    @Test("A tool the phone does not know answers with an error, and the loop goes on")
    func unknownTool() async throws {
        let transport = ScriptedTransport([
            [toolUseTurn(id: "t1", name: "teleport", input: [:])],
            [textTurn("Не получилось, но вот что знаю.")],
        ])
        let conversation = AssistantConversation(transport: transport, toolkit: RecordingToolkit(), language: "en")
        let reply = try await conversation.send("Hi")
        #expect(reply.text == "Не получилось, но вот что знаю.")
        #expect(conversation.messages[2].content.first?["is_error"] == true)
    }

    @Test("An endless tool loop stops")
    func tooManySteps() async throws {
        let script = (0..<3).map { _ in [toolUseTurn(id: "t", name: "list_trophies", input: [:])] }
        let conversation = AssistantConversation(transport: ScriptedTransport(script), toolkit: RecordingToolkit(), language: "ru", maxSteps: 3)
        await #expect(throws: AssistantConversationError.tooManySteps) {
            _ = try await conversation.send("Hi")
        }
    }

    @Test("A long history loses its oldest questions, whole")
    func trim() {
        var messages: [AssistantWireMessage] = []
        for index in 0..<60 {
            messages.append(AssistantWireMessage(role: .user, content: [AssistantWireMessage.textBlock("q\(index)")]))
            messages.append(AssistantWireMessage(role: .assistant, content: [AssistantWireMessage.textBlock("a\(index)")]))
        }
        let conversation = AssistantConversation(transport: ScriptedTransport([]), toolkit: RecordingToolkit(), language: "ru", messages: messages)
        #expect(conversation.trimIfNeeded())
        #expect(conversation.messages.count <= AssistantConversation.maxKeptMessages)
        #expect(conversation.messages.first?.role == .user)
    }
}
