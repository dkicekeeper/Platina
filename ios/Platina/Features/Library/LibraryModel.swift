import Foundation
import Observation
import PSNKit

/// The library screen's data: the profile and the PS5 trophy lists, straight from PSN. Stage 1
/// puts a local store under it (docs/PLAN.md §9).
@MainActor
@Observable
final class LibraryModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var profile: PSNProfile?
    private(set) var summary: TrophySummary?
    private(set) var games: [TrophyTitle] = []
    private(set) var hasLoaded = false

    private let client: PSNClient
    private let onError: (any Error) -> Void

    init(client: PSNClient, onError: @escaping (any Error) -> Void) {
        self.client = client
        self.onError = onError
    }

    var platinumCount: Int { games.filter(\.isPlatinumEarned).count }

    func load() async {
        if games.isEmpty { state = .loading }
        do {
            async let summary = client.trophySummary()
            async let titles = client.trophyTitles()
            async let profile = client.profile()
            let loadedSummary = try await summary
            let loadedTitles = try await titles
            self.summary = loadedSummary
            // Only PS5 for now (docs/PLAN.md §10). Most recent change first, as PSN sorts.
            games = loadedTitles.filter(\.isPS5)
            self.profile = try? await profile
            state = .loaded
            hasLoaded = true
        } catch {
            onError(error)
            if games.isEmpty {
                state = .failed(error.userMessage)
            }
        }
    }
}
