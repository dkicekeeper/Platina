import Foundation
import Testing
import PSNKit
@testable import PlatinaCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ string: String) -> Date {
    PSNDate.parse(string)!
}

private func title(_ id: String, updated: String, version: String = "01.00", groups: Bool = false) -> TrophyTitle {
    TrophyTitle(
        npCommunicationId: id, trophySetVersion: version, trophyTitleName: id, hasTrophyGroups: groups,
        definedTrophies: TrophyCounts(bronze: 10, silver: 3, gold: 1, platinum: 1),
        earnedTrophies: TrophyCounts(bronze: 2), progress: 10, lastUpdatedDateTime: date(updated)
    )
}

private func game(
    _ id: String, name: String? = nil, progress: Int, earned: TrophyCounts, defined: TrophyCounts = TrophyCounts(bronze: 10, silver: 3, gold: 1, platinum: 1),
    updated: String = "2026-11-01T00:00:00Z", playTime: TimeInterval? = nil, status: GamePlanStatus = .none
) -> GameSummary {
    GameSummary(id: id, name: name ?? id, progress: progress, defined: defined, earned: earned,
                lastUpdated: date(updated), playTime: playTime, status: status)
}

@Suite("Sync planner")
struct SyncPlannerTests {
    @Test("New, changed and patched games need their trophies; unchanged ones do not")
    func staleness() {
        let stored = DetailState(lastUpdated: date("2026-11-01T10:00:00Z"), trophySetVersion: "01.00", hasGroups: true)
        #expect(SyncPlanner.needsDetails(title("A", updated: "2026-11-01T10:00:00Z"), stored: nil))
        #expect(!SyncPlanner.needsDetails(title("A", updated: "2026-11-01T10:00:00Z"), stored: stored))
        #expect(SyncPlanner.needsDetails(title("A", updated: "2026-11-02T10:00:00Z"), stored: stored))
        #expect(SyncPlanner.needsDetails(title("A", updated: "2026-11-01T10:00:00Z", version: "01.10"), stored: stored))

        let noGroups = DetailState(lastUpdated: date("2026-11-01T10:00:00Z"), trophySetVersion: "01.00", hasGroups: false)
        #expect(SyncPlanner.needsDetails(title("A", updated: "2026-11-01T10:00:00Z", groups: true), stored: noGroups))
    }

    @Test("Newest first, within the request budget, the rest deferred")
    func budget() {
        let titles = [
            title("old", updated: "2026-01-01T00:00:00Z"),
            title("new", updated: "2026-11-01T00:00:00Z", groups: true),
            title("mid", updated: "2026-06-01T00:00:00Z"),
        ]
        let plan = SyncPlanner.plan(titles: titles, stored: [:], requestBudget: 5)
        #expect(plan.items.map(\.title.id) == ["new", "mid"])
        #expect(plan.items.map(\.fetchesGroups) == [true, false])
        #expect(plan.requestCount == 5)
        #expect(plan.deferred == 1)
    }

    @Test("The game on screen goes first; one game goes even over the budget")
    func priority() {
        let titles = [title("new", updated: "2026-11-01T00:00:00Z"), title("open", updated: "2025-01-01T00:00:00Z", groups: true)]
        let plan = SyncPlanner.plan(titles: titles, stored: [:], requestBudget: 1, priority: "open")
        #expect(plan.items.map(\.title.id) == ["open"])
        #expect(plan.deferred == 1)
    }
}

@Suite("Time played")
struct PlayTimeTests {
    let played = [
        PlayedGame(titleId: "PPSA1", name: "Game EU", imageUrl: "https://img/eu.png", playCount: 3,
                   firstPlayedDateTime: date("2026-01-01T00:00:00Z"), lastPlayedDateTime: date("2026-02-01T00:00:00Z"), playDuration: "PT10H",
                   concept: .init(media: .init(images: [
                       PSNGameArt(url: "https://img/eu-poster.jpg", type: PSNGameArt.portraitBanner),
                       PSNGameArt(url: "https://img/eu-hub.jpg", type: PSNGameArt.gameHubCoverArt),
                       PSNGameArt(url: "https://img/eu-logo.png", type: PSNGameArt.logo),
                       PSNGameArt(url: "https://img/eu-backdrop.jpg", type: PSNGameArt.backgroundLayerArt),
                       PSNGameArt(url: "https://img/eu-hero.png", type: PSNGameArt.heroCharacter),
                   ]))),
        PlayedGame(titleId: "PPSA2", name: "Game US", imageUrl: "https://img/us.png", playCount: 1,
                   firstPlayedDateTime: date("2026-03-01T00:00:00Z"), lastPlayedDateTime: date("2026-03-02T00:00:00Z"), playDuration: "PT30M",
                   // A character with no backdrop: not the hub's layers, nor key art.
                   concept: .init(media: .init(images: [
                       PSNGameArt(url: "https://img/us-hero.png", type: PSNGameArt.heroCharacter),
                   ]))),
        PlayedGame(titleId: "PPSA3", name: "No trophies", lastPlayedDateTime: date("2026-04-01T00:00:00Z"), playDuration: "PT1H"),
    ]

    @Test("Titles not asked yet, most recently played first")
    func unlinked() {
        #expect(PlayTimeLinker.unlinkedTitleIds(played: played, known: ["PPSA2"]) == ["PPSA3", "PPSA1"])
        #expect(PlayTimeLinker.unlinkedTitleIds(played: played, known: [], limit: 1) == ["PPSA3"])
    }

    @Test("Regions of one trophy list add up")
    func sums() throws {
        let time = PlayTimeLinker.playTime(played: played, links: ["PPSA1": ["NPWR1"], "PPSA2": ["NPWR1"], "PPSA3": []])
        let game = try #require(time["NPWR1"])
        #expect(game.seconds == 10.5 * 3600)
        #expect(game.playCount == 4)
        #expect(game.firstPlayed == date("2026-01-01T00:00:00Z"))
        #expect(game.lastPlayed == date("2026-03-02T00:00:00Z"))
        #expect(game.imageURL?.absoluteString == "https://img/us.png")
        #expect(game.titleIds == ["PPSA1", "PPSA2"])
        // The latest title has only a character: the older region's key art, the game hub's
        // cover first, and its layers, both from it.
        #expect(game.artURL?.absoluteString == "https://img/eu-hub.jpg")
        #expect(game.logoURL?.absoluteString == "https://img/eu-logo.png")
        #expect(game.heroLayers?.backdrop.absoluteString == "https://img/eu-backdrop.jpg")
        #expect(game.heroLayers?.character.absoluteString == "https://img/eu-hero.png")
        #expect(time.count == 1)
    }
}

@Suite("Library filters")
struct LibraryFilterTests {
    let games = [
        game("plat", name: "Astro Bot", progress: 100, earned: TrophyCounts(bronze: 10, silver: 3, gold: 1, platinum: 1), updated: "2026-10-01T00:00:00Z", playTime: 20 * 3600),
        game("half", name: "Elden Ring", progress: 45, earned: TrophyCounts(bronze: 5), updated: "2026-11-10T00:00:00Z", playTime: 80 * 3600),
        game("new", name: "Cult of the Lamb", progress: 0, earned: TrophyCounts(), updated: "2026-11-15T00:00:00Z"),
        game("later", name: "Bloodborne", progress: 12, earned: TrophyCounts(bronze: 2), updated: "2026-05-01T00:00:00Z", status: .later),
    ]

    @Test("Each shelf")
    func shelves() {
        #expect(games.filtered(shelf: .platinum, sort: .recent).map(\.id) == ["plat"])
        #expect(games.filtered(shelf: .completed, sort: .recent).map(\.id) == ["plat"])
        #expect(games.filtered(shelf: .inProgress, sort: .recent).map(\.id) == ["half"])
        #expect(games.filtered(shelf: .notStarted, sort: .recent).map(\.id) == ["new"])
        #expect(games.filtered(shelf: .shelved, sort: .recent).map(\.id) == ["later"])
        #expect(games.counts()[.all] == 4)
    }

    @Test("Orders and search")
    func ordersAndSearch() {
        #expect(games.filtered(shelf: .all, sort: .recent).map(\.id) == ["new", "half", "plat", "later"])
        #expect(games.filtered(shelf: .all, sort: .progress).map(\.id) == ["plat", "half", "later", "new"])
        #expect(games.filtered(shelf: .all, sort: .name).map(\.id) == ["plat", "later", "new", "half"])
        #expect(games.filtered(shelf: .all, sort: .playTime).map(\.id) == ["half", "plat", "new", "later"])
        #expect(games.filtered(shelf: .all, query: "ring", sort: .recent).map(\.id) == ["half"])
    }
}

@Suite("Statistics")
struct StatsTests {
    private func trophy(_ id: Int, _ type: TrophyType, _ at: String, rate: Double?) -> EarnedTrophy {
        EarnedTrophy(gameId: "G", gameName: "Game", trophyId: id, name: "T\(id)", type: type, earnedAt: date(at), earnedRate: rate, iconURL: nil)
    }

    @Test("Totals, months, rarest, platinums and streaks")
    func compute() {
        let games = [
            game("A", progress: 100, earned: TrophyCounts(bronze: 10, silver: 3, gold: 1, platinum: 1), playTime: 3600),
            game("B", progress: 50, earned: TrophyCounts(bronze: 4), playTime: 1800),
            game("C", progress: 0, earned: TrophyCounts()),
        ]
        let trophies = [
            trophy(1, .bronze, "2026-11-18T10:00:00Z", rate: 50),
            trophy(2, .gold, "2026-11-19T10:00:00Z", rate: 3.2),
            trophy(3, .platinum, "2026-11-19T20:00:00Z", rate: 1.1),
            trophy(4, .bronze, "2026-09-02T10:00:00Z", rate: nil),
            trophy(5, .silver, "2025-08-01T10:00:00Z", rate: 20),
        ]
        let stats = StatsCalculator.compute(games: games, trophies: trophies, now: date("2026-11-20T09:00:00Z"), calendar: utc, rarestCount: 2)

        #expect(stats.gameCount == 3)
        #expect(stats.platinumCount == 1)
        #expect(stats.completedCount == 1)
        #expect(stats.averageCompletion == 75)
        #expect(stats.earned.total == 19)
        #expect(stats.totalPlayTime == 5400)

        #expect(stats.months.count == 12)
        #expect(stats.months.last?.month == date("2026-11-01T00:00:00Z"))
        #expect(stats.months.last?.count == 3)
        #expect(stats.months.last?.isCurrent == true)
        #expect(stats.months.first?.month == date("2025-12-01T00:00:00Z"))
        #expect(stats.months.first { $0.month == date("2026-09-01T00:00:00Z") }?.count == 1)

        #expect(stats.days[date("2026-11-19T00:00:00Z")] == 2)
        #expect(stats.rarest.map(\.trophyId) == [3, 2])
        #expect(stats.platinums.map(\.trophyId) == [3])
        #expect(stats.currentStreak == 2)
        #expect(stats.bestStreak == 2)
    }

    @Test("A streak ends when yesterday had no trophy")
    func brokenStreak() {
        let trophies = [trophy(1, .bronze, "2026-11-10T10:00:00Z", rate: nil), trophy(2, .bronze, "2026-11-11T10:00:00Z", rate: nil)]
        let stats = StatsCalculator.compute(games: [], trophies: trophies, now: date("2026-11-20T09:00:00Z"), calendar: utc)
        #expect(stats.currentStreak == 0)
        #expect(stats.bestStreak == 2)
    }
}
