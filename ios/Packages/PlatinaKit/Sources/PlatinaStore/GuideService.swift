#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData
import PlatinaAssistant

/// Guides to games (docs/assistant.md §4): the stored one first, then the server's cache, then
/// a build (Stratege.ru and the web, a minute or two). A build costs money, so it runs when the
/// person asks for it or Plati needs it, never on its own.
@MainActor
@Observable
public final class GuideService {
    public enum BuildState: Equatable {
        case idle
        case building(step: String)
        case failed(String)
    }

    public private(set) var states: [String: BuildState] = [:]
    /// Bumped on every stored guide, so views reading `guide(for:)` redraw.
    public private(set) var revision = 0

    private let store: LibraryStore
    private let transport: (any AssistantTransport)?
    private let language: String
    private let now: () -> Date
    @ObservationIgnored private var memory: [String: Guide] = [:]

    public init(store: LibraryStore, transport: (any AssistantTransport)?, language: String, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.transport = transport
        self.language = language
        self.now = now
    }

    public var isAvailable: Bool { transport != nil }

    public func state(for gameId: String) -> BuildState { states[gameId] ?? .idle }

    /// The stored guide of a game, if any.
    public func guide(for gameId: String) -> Guide? {
        _ = revision
        if let cached = memory[gameId] { return cached }
        let key = "\(gameId):\(language)"
        var descriptor = FetchDescriptor<GuideRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let record = try? store.context.fetch(descriptor).first,
              let guide = try? JSONDecoder().decode(Guide.self, from: record.json) else { return nil }
        memory[gameId] = guide
        return guide
    }

    /// The server's cached guide, if someone already built it: free, so a game's screen asks.
    public func fetchCached(gameId: String) async {
        guard guide(for: gameId) == nil, let transport else { return }
        if let guide = try? await transport.cachedGuide(gameId: gameId, language: language) {
            save(guide, gameId: gameId)
        }
    }

    /// Builds (or rebuilds) a game's guide on the server and stores it.
    @discardableResult
    public func build(gameId: String, refresh: Bool = false) async -> Guide? {
        guard let transport else { return nil }
        if case .building = state(for: gameId) { return nil }
        guard let game = try? store.game(gameId) else { return nil }
        let request = GuideRequest(language: language, refresh: refresh, game: GuideRequest.Game(record: game))
        states[gameId] = .building(step: "start")
        do {
            for try await event in transport.guide(request) {
                switch event {
                case .progress(let step):
                    states[gameId] = .building(step: step)
                case .guide(let guide):
                    save(guide, gameId: gameId)
                    states[gameId] = .idle
                    return guide
                case .error(let code, _):
                    states[gameId] = .failed(code)
                    return nil
                }
            }
            states[gameId] = .failed("no_guide")
        } catch {
            states[gameId] = .failed(String(describing: error))
        }
        return nil
    }

    /// The guide, built if there is none: what Plati's `get_guide` asks.
    public func guideBuildingIfNeeded(gameId: String) async -> Guide? {
        if let guide = guide(for: gameId) { return guide }
        await fetchCached(gameId: gameId)
        if let guide = guide(for: gameId) { return guide }
        return await build(gameId: gameId)
    }

    private func save(_ guide: Guide, gameId: String) {
        guard let data = try? JSONEncoder().encode(guide) else { return }
        let key = "\(gameId):\(language)"
        var descriptor = FetchDescriptor<GuideRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let record = try? store.context.fetch(descriptor).first {
            record.json = data
            record.fetchedAt = now()
        } else {
            store.context.insert(GuideRecord(gameId: gameId, language: language, json: data, fetchedAt: now()))
        }
        try? store.context.save()
        memory[gameId] = guide
        revision += 1
    }
}
#endif
