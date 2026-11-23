#if canImport(SwiftData)
import Foundation
import Observation
import PSNKit

/// PlayStation's Game Help for the trophy screen, the game's trophy list and Plati's
/// `get_game_help` (docs/PLAN.md §5). Which trophies of a game have help is asked once per game a
/// launch; a trophy's help once per trophy a launch: its video's token is short-lived, so nothing
/// is kept longer. A failure is quiet: the help is a bonus.
@MainActor
@Observable
public final class GameHelpService {
    private let client: PSNClient
    @ObservationIgnored private var hints: [String: [GameHelpHint]] = [:]
    @ObservationIgnored private var asking: [String: Task<[GameHelpHint], any Error>] = [:]
    @ObservationIgnored private var known: [String: GameHelp] = [:]

    public init(client: PSNClient) {
        self.client = client
    }

    /// The trophy's help, or nil when it has none or PSN would not say.
    public func help(gameId: String, trophyId: Int) async -> GameHelp? {
        await helps(gameId: gameId, trophyIds: [trophyId])[trophyId]
    }

    /// The help of these trophies, asked in one request for the ones not known yet; trophies
    /// without help are left out.
    public func helps(gameId: String, trophyIds: [Int]) async -> [Int: GameHelp] {
        var found: [Int: GameHelp] = [:]
        var missing: [Int] = []
        for id in trophyIds {
            if let help = known[Self.key(gameId, id)] { found[id] = help } else { missing.append(id) }
        }
        guard !missing.isEmpty, let hints = try? await hints(for: gameId) else { return found }
        let asked = hints.filter { hint in hint.trophyNumber.map { missing.contains($0) } ?? false }
        guard !asked.isEmpty,
              let answer = try? await client.gameHelp(npCommunicationId: gameId, hints: asked) else {
            return found
        }
        for help in answer where !help.tips.isEmpty {
            known[Self.key(gameId, help.trophyId)] = help
            found[help.trophyId] = help
        }
        return found
    }

    private static func key(_ gameId: String, _ trophyId: Int) -> String {
        "\(gameId)#\(trophyId)"
    }

    /// The trophies of a game that have help: a mark in the game's list. Empty when PSN would
    /// not say.
    public func helpedTrophyIds(gameId: String) async -> Set<Int> {
        guard let hints = try? await hints(for: gameId) else { return [] }
        return Set(hints.compactMap(\.trophyNumber))
    }

    /// Whether the trophy has help, without asking for it: for the trophy screen's first look.
    public func hasHelp(gameId: String, trophyId: Int) async -> Bool {
        guard let hints = try? await hints(for: gameId) else { return false }
        return hints.contains { $0.trophyNumber == trophyId }
    }

    private func hints(for gameId: String) async throws -> [GameHelpHint] {
        if let known = hints[gameId] { return known }
        if let running = asking[gameId] { return try await running.value }
        let client = client
        let task = Task { try await client.gameHelpHints(npCommunicationId: gameId) }
        asking[gameId] = task
        defer { asking[gameId] = nil }
        let answer = try await task.value
        hints[gameId] = answer
        return answer
    }
}
#endif
