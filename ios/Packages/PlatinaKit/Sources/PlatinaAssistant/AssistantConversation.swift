import Foundation

/// The server, as the conversation sees it: tests answer with scripts.
public protocol AssistantTransport: Sendable {
    func turn(_ request: AssistantTurnRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>
    func guide(_ request: GuideRequest) -> AsyncThrowingStream<GuideStreamEvent, Error>
    func cachedGuide(gameId: String, language: String) async throws -> Guide?
}

/// Executes one tool on the phone (docs/assistant.md §5).
@MainActor
public protocol AssistantToolExecuting: AnyObject {
    func execute(name: String, input: JSONValue) async -> AssistantToolOutput
}

public struct AssistantToolOutput: Sendable, Equatable {
    public let value: JSONValue?
    public let error: String?

    public static func success(_ value: JSONValue) -> AssistantToolOutput { AssistantToolOutput(value: value, error: nil) }
    public static func failure(_ message: String) -> AssistantToolOutput { AssistantToolOutput(value: nil, error: message) }
}

/// A photo sent with a message ("where am I?"): a JPEG, PNG or WebP, inline.
public struct AssistantImage: Sendable, Equatable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String = "image/jpeg") {
        self.data = data
        self.mediaType = mediaType
    }

    var block: JSONValue {
        [
            "type": "image",
            "source": ["type": "base64", "media_type": .string(mediaType), "data": .string(data.base64EncodedString())],
        ]
    }
}

public enum AssistantConversationError: Error, Equatable {
    /// The turn ended without any text.
    case noReply
    case tooManySteps
    case stream(code: String, retryable: Bool)
}

/// Runs Plati's loop for one thread (from Tenra's AgentConversation): send the conversation,
/// execute the tools Claude asks for on the phone, send their results, until it answers in text.
/// History is append-only: assistant turns are kept as the server returned them, or the
/// thinking blocks and the prompt cache break. A failed turn is rolled back.
@MainActor
public final class AssistantConversation {
    public enum Progress: Equatable, Sendable {
        /// A phone tool started.
        case tool(String)
        /// A web search started.
        case search(String)
        /// The reply's text so far (of the current model call).
        case text(String)
    }

    public struct Reply: Equatable, Sendable {
        public let text: String
        /// The tools the turn used, in order.
        public let tools: [String]
    }

    public private(set) var messages: [AssistantWireMessage]

    private let transport: any AssistantTransport
    private let toolkit: any AssistantToolExecuting
    private let language: String
    private let maxSteps: Int

    public init(
        transport: any AssistantTransport,
        toolkit: any AssistantToolExecuting,
        language: String,
        messages: [AssistantWireMessage] = [],
        maxSteps: Int = 10
    ) {
        self.transport = transport
        self.toolkit = toolkit
        self.language = language
        self.messages = messages
        self.maxSteps = maxSteps
    }

    /// The server takes at most 80 messages and 256 KB; one turn adds up to 1 + 2 × maxSteps.
    public static let maxKeptMessages = 50
    public static let maxKeptBytes = 128 * 1024
    /// Photos kept in the history; with the one being sent, the server's limit of three.
    public static let maxKeptImages = 2

    private static func imageBlocks(_ message: AssistantWireMessage) -> [JSONValue] {
        message.content.filter { $0["type"]?.stringValue == "image" }
    }

    private static func imageCount(_ message: AssistantWireMessage) -> Int { imageBlocks(message).count }

    private static func imageChars(_ message: AssistantWireMessage) -> Int {
        imageBlocks(message).reduce(0) { $0 + ($1.value(atPath: "source.data")?.stringValue?.count ?? 0) }
    }

    /// Over the limits, the oldest questions go, whole: the history then starts at a question.
    /// Returns whether anything went (the `<app_context>` went with it, so it is sent again).
    @discardableResult
    public func trimIfNeeded() -> Bool {
        let encoder = JSONEncoder()
        // Photos count by number, not bytes: at most maxKeptImages stay.
        let sizes = messages.map { max(0, ((try? encoder.encode($0).count) ?? 0) - Self.imageChars($0)) }
        let images = messages.map(Self.imageCount)
        var earliest = max(0, messages.count - Self.maxKeptMessages)
        var keptBytes = sizes[earliest...].reduce(0, +)
        var keptImages = images[earliest...].reduce(0, +)
        while (keptBytes > Self.maxKeptBytes || keptImages > Self.maxKeptImages), earliest < messages.count - 1 {
            keptBytes -= sizes[earliest]
            keptImages -= images[earliest]
            earliest += 1
        }
        guard earliest > 0 else { return false }
        guard let start = messages.indices.dropFirst(earliest).first(where: { index in
            messages[index].role == .user && messages[index].content.contains { $0["type"]?.stringValue == "text" }
        }) else { return false }
        var kept = Array(messages[start...])
        kept[0] = AssistantWireMessage(role: .user, content: kept[0].content.filter { $0["type"]?.stringValue != "tool_result" })
        messages = kept
        return true
    }

    /// Sends one message and runs the loop to the reply.
    /// - Parameter context: the `<app_context>` block, on the thread's first message and
    ///   whenever it changes.
    public func send(
        _ text: String,
        image: AssistantImage? = nil,
        context: String? = nil,
        onProgress: ((Progress) -> Void)? = nil
    ) async throws -> Reply {
        let checkpoint = messages.count
        var content: [JSONValue] = []
        if let context { content.append(AssistantWireMessage.textBlock(context)) }
        if let image { content.append(image.block) }
        content.append(AssistantWireMessage.textBlock(text))
        messages.append(AssistantWireMessage(role: .user, content: content))
        do {
            return try await run(onProgress: onProgress)
        } catch {
            messages.removeSubrange(checkpoint...)
            throw error
        }
    }

    private func run(onProgress: ((Progress) -> Void)?) async throws -> Reply {
        var tools: [String] = []
        for _ in 0..<maxSteps {
            var finished: AssistantTurnDone?
            var streamed = ""
            let request = AssistantTurnRequest(language: language, messages: messages)
            for try await event in transport.turn(request) {
                switch event {
                case .text(let piece):
                    streamed += piece
                    onProgress?(.text(streamed))
                case .tool(let name):
                    onProgress?(.tool(name))
                case .search(let query):
                    onProgress?(.search(query))
                case .done(let turn):
                    finished = turn
                case .error(let code, let retryable):
                    throw AssistantConversationError.stream(code: code, retryable: retryable)
                }
            }
            guard let done = finished else { throw AssistantConversationError.noReply }
            let message = AssistantWireMessage(role: .assistant, content: done.content)
            messages.append(message)

            let uses = done.content.compactMap(AssistantToolUse.init(block:))
            guard !uses.isEmpty, done.stopReason == "tool_use" else {
                let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                // Cards alone are an answer too.
                let showedCards = tools.contains { AssistantProtocol.Tool(rawValue: $0)?.isDisplay == true }
                guard !text.isEmpty || showedCards else { throw AssistantConversationError.noReply }
                return Reply(text: text, tools: tools)
            }
            var results: [JSONValue] = []
            for use in uses {
                tools.append(use.name)
                let output = await toolkit.execute(name: use.name, input: use.input)
                if let value = output.value {
                    results.append(AssistantToolResult(toolUseId: use.id, content: value.jsonString(), isError: false).block)
                } else {
                    results.append(AssistantToolResult(toolUseId: use.id, content: output.error ?? "Tool failed", isError: true).block)
                }
            }
            messages.append(AssistantWireMessage(role: .user, content: results))
        }
        throw AssistantConversationError.tooManySteps
    }
}
