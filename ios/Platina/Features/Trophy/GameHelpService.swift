import Foundation
import Observation
import PSNKit

/// PlayStation's Game Help for the trophy screen (docs/PLAN.md §5). Which trophies of a game have
/// help is asked once per game a launch; a trophy's help once per trophy a launch: its video's
/// token is short-lived, so nothing is kept longer. A failure is quiet: the help is a bonus.
@MainActor
@Observable
final class GameHelpService {
    private let client: PSNClient
    @ObservationIgnored private var hints: [String: [GameHelpHint]] = [:]
    @ObservationIgnored private var asking: [String: Task<[GameHelpHint], any Error>] = [:]
    @ObservationIgnored private var helps: [String: GameHelp] = [:]

    init(client: PSNClient) {
        self.client = client
    }

    /// The trophy's help, or nil when it has none or PSN would not say.
    func help(gameId: String, trophyId: Int) async -> GameHelp? {
        let key = "\(gameId)#\(trophyId)"
        if let help = helps[key] { return help }
        guard let hints = try? await hints(for: gameId),
              let hint = hints.first(where: { $0.trophyNumber == trophyId }),
              let help = try? await client.gameHelp(npCommunicationId: gameId, hints: [hint]).first,
              !help.tips.isEmpty else {
            return nil
        }
        helps[key] = help
        return help
    }

    /// Whether the trophy has help, without asking for it: for the trophy screen's first look.
    func hasHelp(gameId: String, trophyId: Int) async -> Bool {
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
