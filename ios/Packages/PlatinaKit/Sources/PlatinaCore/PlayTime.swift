import Foundation
import PSNKit

/// The time spent in a game, from PSN's game list (PS4 and PS5 only).
public struct PlayTime: Sendable, Hashable {
    public let seconds: TimeInterval
    public let firstPlayed: Date?
    public let lastPlayed: Date?
    public let playCount: Int
    /// The game's cover from the game list: bigger and nicer than the trophy list's icon.
    public let imageURL: URL?
    /// The game titles (`PPSA…_00`) counted in it.
    public let titleIds: [String]

    public init(seconds: TimeInterval, firstPlayed: Date?, lastPlayed: Date?, playCount: Int, imageURL: URL?, titleIds: [String]) {
        self.seconds = seconds
        self.firstPlayed = firstPlayed
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.imageURL = imageURL
        self.titleIds = titleIds
    }
}

/// Joins the game list (time by game title) to the trophy lists (`NPWR…`): PSN answers which
/// trophy lists a title has, five titles a request, and the answer never changes, so each title
/// is asked once.
public enum PlayTimeLinker {
    /// Game titles not asked about yet, most recently played first.
    public static func unlinkedTitleIds(played: [PlayedGame], known: Set<String>, limit: Int = 50) -> [String] {
        let ordered = played.sorted { ($0.lastPlayedDateTime ?? .distantPast) > ($1.lastPlayedDateTime ?? .distantPast) }
        var seen = Set<String>()
        var ids: [String] = []
        for game in ordered where !known.contains(game.titleId) && seen.insert(game.titleId).inserted {
            ids.append(game.titleId)
            if ids.count == limit { break }
        }
        return ids
    }

    /// The time per trophy list. A list played under several titles (regions, editions) adds
    /// them up; a title with several lists (a game and its bundled DLC list) counts for each.
    /// - Parameter links: title id → the trophy lists it has.
    public static func playTime(played: [PlayedGame], links: [String: [String]]) -> [String: PlayTime] {
        var byList: [String: [PlayedGame]] = [:]
        for game in played {
            for listId in links[game.titleId] ?? [] {
                byList[listId, default: []].append(game)
            }
        }
        return byList.mapValues { games in
            let latest = games.max { ($0.lastPlayedDateTime ?? .distantPast) < ($1.lastPlayedDateTime ?? .distantPast) }
            return PlayTime(
                seconds: games.reduce(0) { $0 + ($1.timePlayed ?? 0) },
                firstPlayed: games.compactMap(\.firstPlayedDateTime).min(),
                lastPlayed: games.compactMap(\.lastPlayedDateTime).max(),
                playCount: games.reduce(0) { $0 + ($1.playCount ?? 0) },
                imageURL: latest?.imageURL,
                titleIds: games.map(\.titleId).sorted()
            )
        }
    }
}
