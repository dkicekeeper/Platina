#if canImport(SwiftData)
import Foundation
import SwiftData
import PSNKit
import PlatinaCore

// Two stores (docs/architecture.md):
// - the cache: what PSN says (games, trophies, the profile). A sync can rebuild it, so a version
//   that cannot open it simply starts it over;
// - the person's own data (plans for games, later notes and sessions). Built for iCloud: every
//   attribute has a default, nothing is unique, no relationships into the cache (games are
//   referred to by id).

// MARK: - Cache

/// A PS5 trophy list: a game.
@Model
public final class GameRecord {
    /// `NPWR28536_00`.
    @Attribute(.unique) public var id: String
    public var name: String
    public var iconURLString: String?
    /// The cover from the game list, when the game has time played.
    public var coverURLString: String?
    /// The store's key art (the PS5 game hub's cover, a background, the poster) and title logo,
    /// from the game list: the top of the game's screen.
    public var artURLString: String?
    public var logoURLString: String?
    /// The game hub's cover in two layers, when the store has both: its backdrop and the hero
    /// character in front of it (a transparent square). The top of the game's screen stands the
    /// character whole under the bars; without them, the key art.
    public var backdropURLString: String?
    public var characterURLString: String?
    public var platform: String
    public var serviceName: String
    public var trophySetVersion: String
    public var hasTrophyGroups: Bool
    public var progress: Int
    /// When PSN last saw a trophy change in it.
    public var lastUpdated: Date

    public var definedBronze: Int
    public var definedSilver: Int
    public var definedGold: Int
    public var definedPlatinum: Int
    public var earnedBronze: Int
    public var earnedSilver: Int
    public var earnedGold: Int
    public var earnedPlatinum: Int

    /// `lastUpdated` and `trophySetVersion` when the trophies were last fetched (nil: never).
    public var detailsLastUpdated: Date?
    public var detailsVersion: String?

    public var playSeconds: Double?
    public var firstPlayed: Date?
    public var lastPlayed: Date?
    public var playCount: Int?

    @Relationship(deleteRule: .cascade, inverse: \TrophyRecord.game)
    public var trophies: [TrophyRecord] = []
    @Relationship(deleteRule: .cascade, inverse: \TrophyGroupRecord.game)
    public var groups: [TrophyGroupRecord] = []

    public init(title: TrophyTitle) {
        id = title.npCommunicationId
        name = title.trophyTitleName
        platform = title.trophyTitlePlatform
        serviceName = title.npServiceName
        trophySetVersion = title.trophySetVersion
        hasTrophyGroups = title.hasTrophyGroups
        progress = title.progress
        lastUpdated = title.lastUpdatedDateTime
        definedBronze = 0
        definedSilver = 0
        definedGold = 0
        definedPlatinum = 0
        earnedBronze = 0
        earnedSilver = 0
        earnedGold = 0
        earnedPlatinum = 0
        update(from: title)
    }

    func update(from title: TrophyTitle) {
        name = title.trophyTitleName
        iconURLString = title.trophyTitleIconUrl
        platform = title.trophyTitlePlatform
        serviceName = title.npServiceName
        trophySetVersion = title.trophySetVersion
        hasTrophyGroups = title.hasTrophyGroups
        progress = title.progress
        lastUpdated = title.lastUpdatedDateTime
        definedBronze = title.definedTrophies.bronze
        definedSilver = title.definedTrophies.silver
        definedGold = title.definedTrophies.gold
        definedPlatinum = title.definedTrophies.platinum
        earnedBronze = title.earnedTrophies.bronze
        earnedSilver = title.earnedTrophies.silver
        earnedGold = title.earnedTrophies.gold
        earnedPlatinum = title.earnedTrophies.platinum
    }

    public var defined: TrophyCounts {
        TrophyCounts(bronze: definedBronze, silver: definedSilver, gold: definedGold, platinum: definedPlatinum)
    }

    public var earned: TrophyCounts {
        TrophyCounts(bronze: earnedBronze, silver: earnedSilver, gold: earnedGold, platinum: earnedPlatinum)
    }

    public var iconURL: URL? { PSNImageURL.from(iconURLString) }
    public var coverURL: URL? { PSNImageURL.from(coverURLString) }
    public var artURL: URL? { PSNImageURL.from(artURLString) }
    public var logoURL: URL? { PSNImageURL.from(logoURLString) }
    public var backdropURL: URL? { PSNImageURL.from(backdropURLString) }
    public var characterURL: URL? { PSNImageURL.from(characterURLString) }
    public var isPlatinumEarned: Bool { definedPlatinum > 0 && earnedPlatinum > 0 }
    public var isCompleted: Bool { defined.total > 0 && earned.total >= defined.total }
    /// A PS4 game (one with PS5 and PS4 versions is a PS5 game): no Game Help, "PS4" in its rows.
    public var isPS4: Bool {
        let platforms = platform.uppercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return platforms.contains("PS4") && !platforms.contains("PS5")
    }

    /// The trophies are stored and match what PSN says about the game.
    public var hasCurrentDetails: Bool {
        detailsLastUpdated == lastUpdated && detailsVersion == trophySetVersion
    }

    /// The game as a trophy list again, to ask PSN for its trophies.
    public var title: TrophyTitle {
        TrophyTitle(
            npCommunicationId: id, npServiceName: serviceName, trophySetVersion: trophySetVersion,
            trophyTitleName: name, trophyTitleIconUrl: iconURLString, trophyTitlePlatform: platform,
            hasTrophyGroups: hasTrophyGroups, definedTrophies: defined, earnedTrophies: earned,
            progress: progress, lastUpdatedDateTime: lastUpdated
        )
    }

    public func summary(status: GamePlanStatus) -> GameSummary {
        GameSummary(
            id: id, name: name, progress: progress, defined: defined, earned: earned,
            lastUpdated: lastUpdated, playTime: playSeconds, status: status
        )
    }
}

/// A trophy of a game, with the person's progress on it.
@Model
public final class TrophyRecord {
    /// `NPWR28536_00#12`.
    @Attribute(.unique) public var key: String
    public var gameId: String
    public var trophyId: Int
    public var groupId: String
    public var typeRaw: String
    public var name: String
    public var detail: String
    public var iconURLString: String?
    public var isHidden: Bool
    public var isEarned: Bool
    public var earnedAt: Date?
    public var earnedRate: Double?
    public var rarityRaw: Int?
    public var progressCurrent: Int?
    public var progressTarget: Int?
    public var progressUpdatedAt: Date?
    public var game: GameRecord?

    public init(gameId: String, trophy: Trophy) {
        key = Self.key(gameId: gameId, trophyId: trophy.id)
        self.gameId = gameId
        trophyId = trophy.id
        groupId = trophy.groupId
        typeRaw = trophy.type.rawValue
        name = trophy.name
        detail = trophy.detail
        isHidden = trophy.isHidden
        isEarned = trophy.isEarned
        update(from: trophy)
    }

    public static func key(gameId: String, trophyId: Int) -> String {
        "\(gameId)#\(trophyId)"
    }

    func update(from trophy: Trophy) {
        groupId = trophy.groupId
        typeRaw = trophy.type.rawValue
        name = trophy.name
        detail = trophy.detail
        iconURLString = trophy.iconURL?.absoluteString
        isHidden = trophy.isHidden
        isEarned = trophy.isEarned
        earnedAt = trophy.earnedAt
        earnedRate = trophy.earnedRate
        rarityRaw = trophy.rarity?.rawValue
        progressCurrent = trophy.progress?.current
        progressTarget = trophy.progress?.target
        progressUpdatedAt = trophy.progress?.updatedAt
    }

    public var type: TrophyType { TrophyType(rawValue: typeRaw) ?? .bronze }
    public var rarity: TrophyRarity? { rarityRaw.flatMap(TrophyRarity.init(rawValue:)) }
    public var iconURL: URL? { PSNImageURL.from(iconURLString) }

    public var progress: TrophyProgress? {
        guard let progressTarget else { return nil }
        return TrophyProgress(current: progressCurrent ?? 0, target: progressTarget, updatedAt: progressUpdatedAt)
    }
}

/// The base game or a DLC of a game.
@Model
public final class TrophyGroupRecord {
    /// `NPWR28536_00#001`.
    @Attribute(.unique) public var key: String
    public var gameId: String
    public var groupId: String
    public var name: String
    public var detail: String?
    public var iconURLString: String?
    public var definedTotal: Int
    public var game: GameRecord?

    public init(gameId: String, group: TrophyGroup) {
        key = "\(gameId)#\(group.trophyGroupId)"
        self.gameId = gameId
        groupId = group.trophyGroupId
        name = group.trophyGroupName
        definedTotal = group.definedTrophies.total
        update(from: group)
    }

    func update(from group: TrophyGroup) {
        name = group.trophyGroupName
        detail = group.trophyGroupDetail
        iconURLString = group.trophyGroupIconUrl
        definedTotal = group.definedTrophies.total
    }

    public var isBaseGame: Bool { groupId == "default" }
}

/// The signed-in person: level, totals, when the library was last synced.
@Model
public final class ProfileRecord {
    @Attribute(.unique) public var accountId: String
    public var onlineId: String?
    public var avatarURLString: String?
    public var level: Int
    /// Percent towards the next level.
    public var levelProgress: Int
    /// 1–10: the colour of the level's badge.
    public var tier: Int
    public var earnedBronze: Int
    public var earnedSilver: Int
    public var earnedGold: Int
    public var earnedPlatinum: Int
    public var lastSyncedAt: Date?

    public init(summary: TrophySummary) {
        accountId = summary.accountId
        level = summary.level
        levelProgress = summary.progress
        tier = summary.tier
        earnedBronze = summary.earnedTrophies.bronze
        earnedSilver = summary.earnedTrophies.silver
        earnedGold = summary.earnedTrophies.gold
        earnedPlatinum = summary.earnedTrophies.platinum
    }

    func update(summary: TrophySummary, profile: PSNProfile?) {
        level = summary.level
        levelProgress = summary.progress
        tier = summary.tier
        earnedBronze = summary.earnedTrophies.bronze
        earnedSilver = summary.earnedTrophies.silver
        earnedGold = summary.earnedTrophies.gold
        earnedPlatinum = summary.earnedTrophies.platinum
        if let profile {
            onlineId = profile.onlineId
            avatarURLString = profile.avatarURL?.absoluteString
        }
    }

    /// Every platform's trophies, not only PS5's.
    public var earned: TrophyCounts {
        TrophyCounts(bronze: earnedBronze, silver: earnedSilver, gold: earnedGold, platinum: earnedPlatinum)
    }

    public var avatarURL: URL? { PSNImageURL.from(avatarURLString) }
}

/// Which trophy lists a game title (`PPSA…_00`) has. Asked once per title: it never changes.
@Model
public final class TitleLinkRecord {
    @Attribute(.unique) public var titleId: String
    public var listIds: [String]
    public var checkedAt: Date

    public init(titleId: String, listIds: [String], checkedAt: Date) {
        self.titleId = titleId
        self.listIds = listIds
        self.checkedAt = checkedAt
    }
}

/// A PSN friend of the person, for comparing progress in shared games (cache: FriendsSync
/// rebuilds it).
@Model
public final class FriendRecord {
    @Attribute(.unique) public var accountId: String
    public var onlineId: String
    public var avatarURLString: String?
    /// The friend hides their trophies from others: nothing to compare.
    public var isHidden: Bool
    /// When the profile was read (online id and avatar change rarely: weekly).
    public var profileUpdatedAt: Date?
    /// When the trophy lists were read.
    public var titlesUpdatedAt: Date?

    public init(accountId: String) {
        self.accountId = accountId
        onlineId = ""
        isHidden = false
    }

    public var avatarURL: URL? { PSNImageURL.from(avatarURLString) }
}

/// One trophy list of a friend: progress only (the owner's decision, 2026-11-25).
@Model
public final class FriendTitleRecord {
    /// `accountId#NPWR…`.
    @Attribute(.unique) public var key: String
    public var friendId: String
    public var gameId: String
    public var progress: Int
    public var earnedTotal: Int
    public var hasPlatinum: Bool
    public var lastUpdated: Date

    public init(friendId: String, title: TrophyTitle) {
        key = "\(friendId)#\(title.npCommunicationId)"
        self.friendId = friendId
        gameId = title.npCommunicationId
        progress = title.progress
        earnedTotal = title.earnedTrophies.total
        hasPlatinum = title.isPlatinumEarned
        lastUpdated = title.lastUpdatedDateTime
    }
}

/// A game's guide as the server built it (docs/assistant.md §4), kept for offline reading.
@Model
public final class GuideRecord {
    /// `NPWR28536_00:ru`.
    @Attribute(.unique) public var key: String
    public var gameId: String
    public var language: String
    public var json: Data
    public var fetchedAt: Date

    public init(gameId: String, language: String, json: Data, fetchedAt: Date) {
        key = "\(gameId):\(language)"
        self.gameId = gameId
        self.language = language
        self.json = json
        self.fetchedAt = fetchedAt
    }
}

/// A game's walkthrough plan as the server built it (docs/assistant.md §8): `NPWR…:ru`.
@Model
public final class WalkthroughRecord {
    @Attribute(.unique) public var key: String
    public var gameId: String
    public var language: String
    public var json: Data
    public var fetchedAt: Date

    public init(gameId: String, language: String, json: Data, fetchedAt: Date) {
        key = "\(gameId):\(language)"
        self.gameId = gameId
        self.language = language
        self.json = json
        self.fetchedAt = fetchedAt
    }
}

/// A chapter's steps as the server built them: `NPWR…:ru:c3`.
@Model
public final class ChapterRecord {
    @Attribute(.unique) public var key: String
    public var gameId: String
    public var language: String
    public var chapterId: String
    public var json: Data
    public var fetchedAt: Date

    public init(gameId: String, language: String, chapterId: String, json: Data, fetchedAt: Date) {
        key = "\(gameId):\(language):\(chapterId)"
        self.gameId = gameId
        self.language = language
        self.chapterId = chapterId
        self.json = json
        self.fetchedAt = fetchedAt
    }
}

// MARK: - The person's own data

/// What the person plans for a game.
@Model
public final class GamePlanRecord {
    public var gameId: String = ""
    public var statusRaw: String = GamePlanStatus.none.rawValue
    public var updatedAt: Date = Date.distantPast

    public init(gameId: String, status: GamePlanStatus, updatedAt: Date) {
        self.gameId = gameId
        statusRaw = status.rawValue
        self.updatedAt = updatedAt
    }

    public var status: GamePlanStatus { GamePlanStatus(rawValue: statusRaw) ?? .none }
}

/// A play session: a step on the way to a game's platinum (docs/domains/screens.md §3.5).
@Model
public final class PlaySessionRecord {
    public var sessionId: String = ""
    public var gameId: String = ""
    /// The game's name then: the history reads even if the game leaves PSN's list.
    public var gameName: String = ""
    public var startedAt: Date = Date.distantPast
    public var endedAt: Date?
    /// While paused: when the pause began.
    public var pausedAt: Date?
    /// The pauses before the current one, in seconds.
    public var pausedSeconds: Double = 0
    /// The trophies the session aims at.
    public var goalTrophyIds: [Int] = []
    /// Goals ticked by hand (an earned goal is done anyway).
    public var checkedGoalTrophyIds: [Int] = []
    /// Trophies earned while it ran.
    public var earnedTrophyIds: [Int] = []
    public var startProgress: Int = 0
    public var endProgress: Int?
    /// PSN's time played in the game at the start and at the end: the session's real time.
    public var startPlaySeconds: Double?
    public var endPlaySeconds: Double?
    /// "Where I stopped".
    public var note: String = ""
    /// Plati's summary and what to do next (stage 3).
    public var summary: String?
    public var nextSteps: String?

    public init(sessionId: String, gameId: String, gameName: String, startedAt: Date, startProgress: Int, startPlaySeconds: Double?) {
        self.sessionId = sessionId
        self.gameId = gameId
        self.gameName = gameName
        self.startedAt = startedAt
        self.startProgress = startProgress
        self.startPlaySeconds = startPlaySeconds
    }

    public var isRunning: Bool { endedAt == nil }
    public var isPaused: Bool { pausedAt != nil }

    /// Time played by the session's clock, pauses left out.
    public func elapsed(at date: Date) -> TimeInterval {
        let end = endedAt ?? pausedAt ?? date
        return max(0, end.timeIntervalSince(startedAt) - pausedSeconds)
    }

    /// The moment a clock that skips the pauses would have started: what `Text(timerInterval:)`
    /// and `RelativeTime(.clock)` count from.
    public var clockStart: Date { startedAt.addingTimeInterval(pausedSeconds) }

    /// PSN's own count of the time, once the session is over and PSN has both ends.
    public var psnSeconds: Double? {
        guard let start = startPlaySeconds, let end = endPlaySeconds, end >= start else { return nil }
        return end - start
    }

    public func isGoalDone(_ trophyId: Int) -> Bool {
        earnedTrophyIds.contains(trophyId) || checkedGoalTrophyIds.contains(trophyId)
    }
}

/// A conversation with Plati: the general one (`gameId` "") or a game's. The wire history goes
/// back to the server as it is; the display history is what the chat shows.
@Model
public final class ConversationRecord {
    public var gameId: String = ""
    public var messagesData: Data = Data()
    public var displayData: Data = Data()
    public var updatedAt: Date = Date.distantPast

    public init(gameId: String, updatedAt: Date) {
        self.gameId = gameId
        self.updatedAt = updatedAt
    }
}

/// Where the person is in a game's walkthrough, beyond what their trophies say: the steps they
/// ticked (`c2/s5`), the chapters they marked done, the chapter they said they are on ("" when
/// worked out from the rest). One per game; the language of the walkthrough doesn't matter.
@Model
public final class WalkthroughProgressRecord {
    public var gameId: String = ""
    public var checkedSteps: [String] = []
    public var doneChapters: [String] = []
    public var currentChapter: String = ""
    public var updatedAt: Date = Date.distantPast

    public init(gameId: String, updatedAt: Date) {
        self.gameId = gameId
        self.updatedAt = updatedAt
    }
}

/// The person's note on a game or one of its trophies (`trophyId` -1 for the game).
@Model
public final class NoteRecord {
    public var gameId: String = ""
    public var trophyId: Int = -1
    public var text: String = ""
    public var updatedAt: Date = Date.distantPast

    public init(gameId: String, trophyId: Int?, text: String, updatedAt: Date) {
        self.gameId = gameId
        self.trophyId = trophyId ?? -1
        self.text = text
        self.updatedAt = updatedAt
    }
}
#endif
