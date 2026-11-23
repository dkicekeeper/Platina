import Foundation

/// The app ↔ server protocol of Plati (docs/assistant.md). One `POST /v1/turn` is one model
/// call; the app runs the loop and executes the tools on the phone. Messages use the Anthropic
/// Messages format, content blocks kept as `JSONValue` so they go back exactly as they came.
public enum AssistantProtocol {
    public static let version = 1

    /// The phone's tools (docs/assistant.md §5); their definitions live on the server.
    public enum Tool: String, CaseIterable, Sendable {
        case getProfile = "get_profile"
        case listGames = "list_games"
        case getGame = "get_game"
        case listTrophies = "list_trophies"
        case getGuide = "get_guide"
        case getGameHelp = "get_game_help"
        case getWalkthrough = "get_walkthrough"
        case getChapter = "get_chapter"
        case setWalkthroughProgress = "set_walkthrough_progress"
        case getSessions = "get_sessions"
        case getCurrentSession = "get_current_session"
        case setSessionGoals = "set_session_goals"
        case setGameStatus = "set_game_status"
        case saveNote = "save_note"
        case saveSessionSummary = "save_session_summary"
    }
}

public struct AssistantWireMessage: Sendable, Equatable, Codable {
    public enum Role: String, Sendable, Codable { case user, assistant }

    public let role: Role
    public let content: [JSONValue]

    public init(role: Role, content: [JSONValue]) {
        self.role = role
        self.content = content
    }

    public static func textBlock(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    /// The text blocks of the message, joined.
    public var text: String {
        content.compactMap { block in block["type"]?.stringValue == "text" ? block["text"]?.stringValue : nil }
            .joined(separator: "\n\n")
    }
}

public struct AssistantTurnRequest: Sendable, Encodable {
    public let `protocol`: Int
    public let language: String
    public let messages: [AssistantWireMessage]

    public init(language: String, messages: [AssistantWireMessage]) {
        self.protocol = AssistantProtocol.version
        self.language = language
        self.messages = messages
    }
}

/// A tool call Claude asked for, read from an assistant content block.
public struct AssistantToolUse: Sendable, Equatable {
    public let id: String
    public let name: String
    public let input: JSONValue

    public init?(block: JSONValue) {
        guard block["type"]?.stringValue == "tool_use",
              let id = block["id"]?.stringValue,
              let name = block["name"]?.stringValue else { return nil }
        self.id = id
        self.name = name
        input = block["input"] ?? .object([:])
    }
}

/// A tool result the app sends back in the next user message.
public struct AssistantToolResult: Sendable, Equatable {
    public let toolUseId: String
    public let content: String
    public let isError: Bool

    public init(toolUseId: String, content: String, isError: Bool) {
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
    }

    public var block: JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("tool_result"),
            "tool_use_id": .string(toolUseId),
            "content": .string(content),
        ]
        if isError { object["is_error"] = .bool(true) }
        return .object(object)
    }
}

public struct AssistantUsage: Sendable, Equatable, Decodable {
    public let inputTokens: Int?
    public let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// The `done` event: the assistant turn to append verbatim, and how it ended.
public struct AssistantTurnDone: Sendable, Equatable, Decodable {
    public let content: [JSONValue]
    public let stopReason: String?
    public let usage: AssistantUsage?

    enum CodingKeys: String, CodingKey {
        case content, usage
        case stopReason = "stop_reason"
    }

    public init(content: [JSONValue], stopReason: String?, usage: AssistantUsage? = nil) {
        self.content = content
        self.stopReason = stopReason
        self.usage = usage
    }
}

public enum AssistantStreamEvent: Sendable, Equatable {
    /// A piece of the reply's text.
    case text(String)
    /// A phone tool call started (the "looking at the trophies…" step).
    case tool(name: String)
    /// Plati searches the web (the server's web_search).
    case search(query: String)
    case done(AssistantTurnDone)
    case error(code: String, retryable: Bool)
}

/// What the guide's SSE stream says (docs/assistant.md §4).
public enum GuideStreamEvent: Sendable, Equatable {
    case progress(step: String)
    case guide(Guide)
    case error(code: String, retryable: Bool)
}

/// Turns server-sent event lines into payloads. Feed lines in order, then `finish()`.
/// `URLSession.AsyncBytes.lines` drops blank lines, so an event also completes when the next
/// `event:` line arrives (from Tenra's AgentSSEParser).
public struct SSEParser: Sendable {
    public struct Event: Sendable, Equatable {
        public let name: String
        public let data: String
    }

    private var event: String?
    private var data: [String] = []

    public init() {}

    public mutating func feed(line: String) -> Event? {
        if line.isEmpty { return flush() }
        if line.hasPrefix("event:") {
            let pending = flush()
            event = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            return pending
        }
        if line.hasPrefix("data:") {
            data.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    public mutating func finish() -> Event? {
        flush()
    }

    private mutating func flush() -> Event? {
        defer { event = nil; data = [] }
        guard let event, !data.isEmpty else { return nil }
        return Event(name: event, data: data.joined(separator: "\n"))
    }
}

private struct TextPayload: Decodable { let text: String }
private struct NamePayload: Decodable { let name: String }
private struct QueryPayload: Decodable { let query: String? }
private struct StepPayload: Decodable { let step: String }
private struct ErrorPayload: Decodable { let code: String?; let retryable: Bool? }

public extension AssistantStreamEvent {
    init?(_ event: SSEParser.Event) {
        let bytes = Data(event.data.utf8)
        let decoder = JSONDecoder()
        switch event.name {
        case "text":
            guard let payload = try? decoder.decode(TextPayload.self, from: bytes) else { return nil }
            self = .text(payload.text)
        case "tool":
            guard let payload = try? decoder.decode(NamePayload.self, from: bytes) else { return nil }
            self = .tool(name: payload.name)
        case "search":
            self = .search(query: (try? decoder.decode(QueryPayload.self, from: bytes))?.query ?? "")
        case "done":
            guard let payload = try? decoder.decode(AssistantTurnDone.self, from: bytes) else {
                self = .error(code: "invalid_done", retryable: true)
                return
            }
            self = .done(payload)
        case "error":
            let payload = try? decoder.decode(ErrorPayload.self, from: bytes)
            self = .error(code: payload?.code ?? "internal", retryable: payload?.retryable ?? false)
        default:
            return nil
        }
    }
}

public extension GuideStreamEvent {
    init?(_ event: SSEParser.Event) {
        let bytes = Data(event.data.utf8)
        let decoder = JSONDecoder()
        switch event.name {
        case "progress":
            guard let payload = try? decoder.decode(StepPayload.self, from: bytes) else { return nil }
            self = .progress(step: payload.step)
        case "guide":
            guard let guide = try? decoder.decode(Guide.self, from: bytes) else {
                self = .error(code: "invalid_guide", retryable: true)
                return
            }
            self = .guide(guide)
        case "error":
            let payload = try? decoder.decode(ErrorPayload.self, from: bytes)
            self = .error(code: payload?.code ?? "internal", retryable: payload?.retryable ?? false)
        default:
            return nil
        }
    }
}
