import Foundation
import PSNKit

/// An earned trophy, as the statistics need it.
public struct EarnedTrophy: Sendable, Hashable, Identifiable {
    public let gameId: String
    public let gameName: String
    public let trophyId: Int
    public let name: String
    public let type: TrophyType
    public let earnedAt: Date
    /// The share of players who have it, 0–100.
    public let earnedRate: Double?
    public let iconURL: URL?

    public var id: String { "\(gameId)#\(trophyId)" }

    public init(gameId: String, gameName: String, trophyId: Int, name: String, type: TrophyType, earnedAt: Date, earnedRate: Double?, iconURL: URL?) {
        self.gameId = gameId
        self.gameName = gameName
        self.trophyId = trophyId
        self.name = name
        self.type = type
        self.earnedAt = earnedAt
        self.earnedRate = earnedRate
        self.iconURL = iconURL
    }
}

/// Trophies earned in one month.
public struct MonthCount: Sendable, Hashable, Identifiable {
    /// The first moment of the month.
    public let month: Date
    public let count: Int
    public let isCurrent: Bool

    public var id: Date { month }
}

/// The profile screen's numbers (docs/domains/screens.md §3.7).
public struct LibraryStats: Sendable, Equatable {
    public let gameCount: Int
    public let platinumCount: Int
    public let completedCount: Int
    /// The mean progress of the games with at least one trophy, 0–100.
    public let averageCompletion: Double
    public let earned: TrophyCounts
    public let totalPlayTime: TimeInterval
    /// The last twelve months, oldest first, the current one last.
    public let months: [MonthCount]
    /// Trophies per day (the day's first moment), for the activity calendar.
    public let days: [Date: Double]
    /// The rarest trophies earned, rarest first.
    public let rarest: [EarnedTrophy]
    /// Every platinum, the newest first.
    public let platinums: [EarnedTrophy]
    /// Days in a row with a trophy, up to today (or yesterday: today is not over).
    public let currentStreak: Int
    public let bestStreak: Int

    public static let empty = LibraryStats(
        gameCount: 0, platinumCount: 0, completedCount: 0, averageCompletion: 0, earned: TrophyCounts(),
        totalPlayTime: 0, months: [], days: [:], rarest: [], platinums: [], currentStreak: 0, bestStreak: 0
    )
}

public enum StatsCalculator {
    public static func compute(
        games: [GameSummary],
        trophies: [EarnedTrophy],
        now: Date = Date(),
        calendar: Calendar = .current,
        rarestCount: Int = 5
    ) -> LibraryStats {
        let started = games.filter(\.isStarted)
        let earned = games.reduce(into: TrophyCounts()) { total, game in
            total.bronze += game.earned.bronze
            total.silver += game.earned.silver
            total.gold += game.earned.gold
            total.platinum += game.earned.platinum
        }

        var days: [Date: Double] = [:]
        for trophy in trophies {
            days[calendar.startOfDay(for: trophy.earnedAt), default: 0] += 1
        }

        let streaks = streaks(days: Set(days.keys), now: now, calendar: calendar)

        return LibraryStats(
            gameCount: games.count,
            platinumCount: games.filter(\.isPlatinumEarned).count,
            completedCount: games.filter(\.isCompleted).count,
            averageCompletion: started.isEmpty ? 0 : Double(started.reduce(0) { $0 + $1.progress }) / Double(started.count),
            earned: earned,
            totalPlayTime: games.reduce(0) { $0 + ($1.playTime ?? 0) },
            months: months(trophies: trophies, now: now, calendar: calendar),
            days: days,
            rarest: Array(
                trophies
                    .filter { $0.earnedRate != nil }
                    .sorted { ($0.earnedRate ?? 100, $1.earnedAt) < ($1.earnedRate ?? 100, $0.earnedAt) }
                    .prefix(rarestCount)
            ),
            platinums: trophies.filter { $0.type == .platinum }.sorted { $0.earnedAt > $1.earnedAt },
            currentStreak: streaks.current,
            bestStreak: streaks.best
        )
    }

    static func months(trophies: [EarnedTrophy], now: Date, calendar: Calendar) -> [MonthCount] {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        var counts: [Date: Int] = [:]
        for trophy in trophies {
            if let month = calendar.dateInterval(of: .month, for: trophy.earnedAt)?.start {
                counts[month, default: 0] += 1
            }
        }
        return (0..<12).reversed().compactMap { back in
            guard let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) else { return nil }
            return MonthCount(month: month, count: counts[month] ?? 0, isCurrent: back == 0)
        }
    }

    static func streaks(days: Set<Date>, now: Date, calendar: Calendar) -> (current: Int, best: Int) {
        let sorted = days.sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in sorted {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        let today = calendar.startOfDay(for: now)
        guard let last = sorted.last,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              last == today || last == yesterday else {
            return (0, best)
        }
        return (run, best)
    }
}
