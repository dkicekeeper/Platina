#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData
import PlatinaAssistant

/// A message as the chat shows it.
public struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
        /// Something that happened, not said: "the session started", shown as a divider.
        case event
    }

    public let id: String
    public let role: Role
    public var text: String
    public let date: Date
    public var failed: Bool

    public init(id: String = UUID().uuidString, role: Role, text: String, date: Date, failed: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.failed = failed
    }
}

/// One conversation with Plati: the general one or a game's (docs/assistant.md §6). Kept in the
/// person's store after every turn.
@MainActor
@Observable
public final class ChatThread: Identifiable {
    public let gameId: String
    public private(set) var messages: [ChatMessage]
    public private(set) var isResponding = false
    /// The tool or search running now, for the "thinking" line.
    public private(set) var step: String?
    /// The reply as it streams.
    public private(set) var streamingText = ""
    /// The last turn's failure, for its Retry: the server's code.
    public private(set) var failure: String?

    public var id: String { gameId }

    private let conversation: AssistantConversation?
    private let record: ConversationRecord
    private let store: LibraryStore
    private let context: () -> String
    @ObservationIgnored private var lastContext: String?
    @ObservationIgnored private var lastQuestion: (text: String, role: ChatMessage.Role)?
    private let now: () -> Date

    init(
        gameId: String,
        record: ConversationRecord,
        store: LibraryStore,
        transport: (any AssistantTransport)?,
        toolkit: AssistantToolkit,
        language: String,
        context: @escaping () -> String,
        now: @escaping () -> Date
    ) {
        self.gameId = gameId
        self.record = record
        self.store = store
        self.context = context
        self.now = now
        messages = (try? JSONDecoder().decode([ChatMessage].self, from: record.displayData)) ?? []
        let wire = (try? JSONDecoder().decode([AssistantWireMessage].self, from: record.messagesData)) ?? []
        conversation = transport.map {
            AssistantConversation(transport: $0, toolkit: toolkit, language: language, messages: wire)
        }
    }

    public var isAvailable: Bool { conversation != nil }

    /// Sends a message and waits for Plati's answer.
    /// - Parameter role: `.event` for what the app says on the person's behalf ("the session
    ///   started"): the chat shows it as a divider, the model reads it as a message.
    public func send(_ text: String, as role: ChatMessage.Role = .user) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }
        messages.append(ChatMessage(role: role, text: trimmed, date: now()))
        await respond(to: trimmed, role: role)
    }

    /// Sends the failed question again.
    public func retry() async {
        guard let lastQuestion, failure != nil, !isResponding else { return }
        if let index = messages.lastIndex(where: { $0.role == lastQuestion.role && $0.text == lastQuestion.text }) {
            messages[index].failed = false
        }
        await respond(to: lastQuestion.text, role: lastQuestion.role)
    }

    /// Starts the thread over.
    public func clear() {
        guard !isResponding else { return }
        messages = []
        failure = nil
        lastContext = nil
        record.messagesData = Data()
        record.displayData = Data()
        record.updatedAt = now()
        try? store.context.save()
        conversationReset?()
    }

    @ObservationIgnored var conversationReset: (() -> Void)?

    private func respond(to text: String, role: ChatMessage.Role) async {
        guard let conversation else {
            failure = "not_configured"
            markFailed(text)
            return
        }
        isResponding = true
        failure = nil
        streamingText = ""
        step = nil
        lastQuestion = (text, role)
        defer {
            isResponding = false
            step = nil
            streamingText = ""
        }
        if conversation.trimIfNeeded() { lastContext = nil }
        let current = context()
        let contextBlock = current == lastContext ? nil : current
        do {
            let reply = try await conversation.send(text, context: contextBlock) { [weak self] progress in
                guard let self else { return }
                switch progress {
                case .tool(let name): step = name
                case .search: step = "web_search"
                case .text(let text): streamingText = text
                }
            }
            lastContext = current
            messages.append(ChatMessage(role: .assistant, text: reply.text, date: now()))
            lastQuestion = nil
        } catch let error as AssistantConversationError {
            switch error {
            case .stream(let code, _): failure = code
            case .noReply: failure = "no_reply"
            case .tooManySteps: failure = "too_many_steps"
            }
            markFailed(text)
        } catch let error as AssistantServerError {
            failure = Self.code(error)
            markFailed(text)
        } catch {
            failure = "offline"
            markFailed(text)
        }
        persist(conversation)
    }

    private func markFailed(_ text: String) {
        if let index = messages.lastIndex(where: { $0.text == text }) {
            messages[index].failed = true
        }
    }

    private func persist(_ conversation: AssistantConversation) {
        record.messagesData = (try? JSONEncoder().encode(conversation.messages)) ?? Data()
        record.displayData = (try? JSONEncoder().encode(messages)) ?? Data()
        record.updatedAt = now()
        try? store.context.save()
    }

    private static func code(_ error: AssistantServerError) -> String {
        switch error {
        case .notConfigured: "not_configured"
        case .invalidRequest: "invalid"
        case .quotaExceeded: "quota"
        case .regionUnavailable: "region_unavailable"
        case .disabled: "disabled"
        case .attestation: "attest"
        case .http: "server"
        }
    }
}

/// Plati (docs/assistant.md): its conversations, its tools, and its part in sessions: a plan at
/// the start, a summary at the end.
@MainActor
@Observable
public final class AssistantService {
    public let isConfigured: Bool
    public let guides: GuideService

    @ObservationIgnored private var threads: [String: ChatThread] = [:]
    private let store: LibraryStore
    private let sessions: SessionTracker
    private let transport: (any AssistantTransport)?
    private let toolkit: AssistantToolkit
    private let language: String
    private let now: () -> Date

    public init(
        store: LibraryStore,
        sessions: SessionTracker,
        transport: (any AssistantTransport)?,
        language: String,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.sessions = sessions
        self.transport = transport
        self.language = language
        self.now = now
        isConfigured = transport != nil
        let guides = GuideService(store: store, transport: transport, language: language, now: now)
        self.guides = guides
        toolkit = AssistantToolkit(store: store, sessions: sessions, guides: guides, now: now)
    }

    /// The conversation about a game (nil: the general one).
    public func thread(gameId: String?) -> ChatThread {
        let key = gameId ?? ""
        if let thread = threads[key] { return thread }
        let record: ConversationRecord
        let descriptor = FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.gameId == key })
        if let existing = try? store.context.fetch(descriptor).first {
            record = existing
        } else {
            record = ConversationRecord(gameId: key, updatedAt: now())
            store.context.insert(record)
            try? store.context.save()
        }
        let thread = ChatThread(
            gameId: key, record: record, store: store, transport: transport, toolkit: toolkit,
            language: language, context: { [weak self] in self?.appContext(gameId: gameId) ?? "" }, now: now
        )
        thread.conversationReset = { [weak self] in
            self?.threads[key] = nil
        }
        threads[key] = thread
        return thread
    }

    /// The start of a session: Plati looks at the guide and the trophies and sets 2–4 goals.
    public func planSession(_ session: PlaySessionRecord) async {
        guard isConfigured else { return }
        let text = language == "en"
            ? "I'm starting a session in \(session.gameName). Plan it: set 2–4 goals for today and warn me about missables."
            : "Начинаю сессию в \(session.gameName). Спланируй её: поставь 2–4 цели на сегодня и предупреди о пропускаемых."
        await thread(gameId: session.gameId).send(text, as: .event)
    }

    /// The end of a session: Plati writes its summary and what to do next into the journal.
    public func summarizeSession(_ session: PlaySessionRecord) async {
        guard isConfigured else { return }
        let minutes = Int(session.elapsed(at: now()) / 60)
        let text = language == "en"
            ? "The session is over: \(minutes) min, \(session.earnedTrophyIds.count) trophies. Write its summary and next steps (save_session_summary, session \(session.sessionId))."
            : "Сессия закончена: \(minutes) мин, трофеев: \(session.earnedTrophyIds.count). Подведи итог и что дальше (save_session_summary, сессия \(session.sessionId))."
        await thread(gameId: session.gameId).send(text, as: .event)
    }

    /// The `<app_context>` block (docs/assistant.md §3).
    func appContext(gameId: String?) -> String {
        var lines: [String] = []
        let today = now()
        lines.append("date: \(today.formatted(.iso8601.year().month().day())) (\(today.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))))")
        lines.append("language: \(language)")
        if let profile = try? store.profile() {
            lines.append("psn: \(profile.onlineId ?? "?"), trophy level \(profile.level)")
        }
        if let gameId, let game = try? store.game(gameId) {
            let status = (try? store.plans()[gameId]) ?? .none
            lines.append("open_game: \(game.id) «\(game.name)», \(game.progress)%, status \(status.rawValue)")
        }
        if let session = sessions.current {
            let minutes = Int(session.elapsed(at: today) / 60)
            let done = session.goalTrophyIds.filter { session.isGoalDone($0) }.count
            lines.append("session: running in \(session.gameId) «\(session.gameName)», id \(session.sessionId), \(minutes) min, goals \(done)/\(session.goalTrophyIds.count), trophies \(session.earnedTrophyIds.count)")
        }
        return "<app_context>\n" + lines.joined(separator: "\n") + "\n</app_context>"
    }
}
#endif
