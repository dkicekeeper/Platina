import Foundation

// The PSN answers the app reads. Field names follow PSN's JSON; optional wherever PSN leaves a
// field out for some titles. Reference: psn-api's models and andshrew/PlayStation-Trophies.

public enum TrophyType: String, Codable, Sendable, CaseIterable, Comparable {
    case platinum, gold, silver, bronze

    /// Platinum first, bronze last: the order of a trophy list and of the counters.
    public static func < (lhs: TrophyType, rhs: TrophyType) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// How rare a trophy is, by PSN's own tiers.
public enum TrophyRarity: Int, Codable, Sendable, Comparable {
    case ultraRare = 0, veryRare = 1, rare = 2, common = 3

    public static func < (lhs: TrophyRarity, rhs: TrophyRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TrophyCounts: Codable, Sendable, Hashable {
    public var bronze: Int
    public var silver: Int
    public var gold: Int
    public var platinum: Int

    public init(bronze: Int = 0, silver: Int = 0, gold: Int = 0, platinum: Int = 0) {
        self.bronze = bronze
        self.silver = silver
        self.gold = gold
        self.platinum = platinum
    }

    public var total: Int { bronze + silver + gold + platinum }

    public subscript(type: TrophyType) -> Int {
        switch type {
        case .bronze: bronze
        case .silver: silver
        case .gold: gold
        case .platinum: platinum
        }
    }
}

// MARK: - Trophy titles (a game's trophy list)

/// One trophy list of the person: a game (or a version of it) with trophies.
public struct TrophyTitle: Decodable, Sendable, Hashable, Identifiable {
    /// `NPWR28536_00`: the trophy list's id, the key of a game everywhere in the app.
    public let npCommunicationId: String
    /// `trophy2` for PS5, `trophy` for PS4, PS3 and Vita: every trophy request needs it.
    public let npServiceName: String
    public let trophySetVersion: String
    public let trophyTitleName: String
    public let trophyTitleIconUrl: String?
    /// `PS5`, `PS4`, `PS3`, `PSVITA`, or several joined by commas.
    public let trophyTitlePlatform: String
    public let trophyTitleDetail: String?
    public let hasTrophyGroups: Bool
    public let definedTrophies: TrophyCounts
    public let earnedTrophies: TrophyCounts
    /// 0–100, weighted by trophy type as PSN counts it.
    public let progress: Int
    public let hiddenFlag: Bool?
    public let lastUpdatedDateTime: Date

    public var id: String { npCommunicationId }
    public var iconURL: URL? { trophyTitleIconUrl.flatMap(URL.init(string:)) }
    public var platforms: [String] {
        trophyTitlePlatform.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
    }
    public var isPS5: Bool { platforms.contains("PS5") }
    public var hasPlatinum: Bool { definedTrophies.platinum > 0 }
    public var isPlatinumEarned: Bool { hasPlatinum && earnedTrophies.platinum > 0 }
    public var isCompleted: Bool { earnedTrophies.total >= definedTrophies.total && definedTrophies.total > 0 }
}

struct TrophyTitlesPage: Decodable, PSNPage {
    let trophyTitles: [TrophyTitle]
    let totalItemCount: Int
    let nextOffset: Int?

    var items: [TrophyTitle] { trophyTitles }
}

// MARK: - Trophy groups (the base game and its DLC)

public struct TrophyGroup: Decodable, Sendable, Hashable, Identifiable {
    /// `default` for the base game, `001`, `002`… for each DLC.
    public let trophyGroupId: String
    public let trophyGroupName: String
    public let trophyGroupDetail: String?
    public let trophyGroupIconUrl: String?
    public let definedTrophies: TrophyCounts

    public var id: String { trophyGroupId }
    public var isBaseGame: Bool { trophyGroupId == "default" }
    public var iconURL: URL? { trophyGroupIconUrl.flatMap(URL.init(string:)) }
}

struct TrophyGroupsResponse: Decodable {
    let trophyGroups: [TrophyGroup]
}

// MARK: - Trophies

/// A trophy as the game defines it: the same for everyone.
struct TrophyDefinition: Decodable, Sendable {
    let trophyId: Int
    let trophyHidden: Bool
    let trophyType: TrophyType
    let trophyName: String?
    let trophyDetail: String?
    let trophyIconUrl: String?
    let trophyGroupId: String?
    let trophyProgressTargetValue: String?
}

struct TrophyDefinitionsPage: Decodable, PSNPage {
    let trophies: [TrophyDefinition]
    let totalItemCount: Int
    let nextOffset: Int?

    var items: [TrophyDefinition] { trophies }
}

/// The person's side of a trophy: earned or not, when, how far along, how rare.
struct TrophyEarning: Decodable, Sendable {
    let trophyId: Int
    let earned: Bool
    let earnedDateTime: Date?
    let trophyRare: TrophyRarity?
    /// A percentage as text: `"12.3"`.
    let trophyEarnedRate: String?
    /// PS5 progress trophies: how far along (`"37"` of a target of `"50"`).
    let progress: String?
    let progressRate: Int?
    let progressedDateTime: Date?
}

struct TrophyEarningsPage: Decodable, PSNPage {
    let trophies: [TrophyEarning]
    let totalItemCount: Int
    let nextOffset: Int?

    var items: [TrophyEarning] { trophies }
}

/// A trophy of a game with the person's progress on it: the definition and the earning together.
public struct Trophy: Sendable, Hashable, Identifiable {
    public let id: Int
    public let groupId: String
    public let type: TrophyType
    public let name: String
    public let detail: String
    public let iconURL: URL?
    public let isHidden: Bool
    public let isEarned: Bool
    public let earnedAt: Date?
    /// The share of players who have it, 0–100.
    public let earnedRate: Double?
    public let rarity: TrophyRarity?
    public let progress: TrophyProgress?

    public init(
        id: Int, groupId: String, type: TrophyType, name: String, detail: String, iconURL: URL?,
        isHidden: Bool, isEarned: Bool, earnedAt: Date?, earnedRate: Double?, rarity: TrophyRarity?,
        progress: TrophyProgress?
    ) {
        self.id = id
        self.groupId = groupId
        self.type = type
        self.name = name
        self.detail = detail
        self.iconURL = iconURL
        self.isHidden = isHidden
        self.isEarned = isEarned
        self.earnedAt = earnedAt
        self.earnedRate = earnedRate
        self.rarity = rarity
        self.progress = progress
    }

    init(definition: TrophyDefinition, earning: TrophyEarning?) {
        let target = definition.trophyProgressTargetValue.flatMap { Int($0) }
        let current = earning?.progress.flatMap { Int($0) }
        let progress: TrophyProgress? = target.map {
            TrophyProgress(
                current: current ?? 0,
                target: $0,
                updatedAt: earning?.progressedDateTime
            )
        }
        self.init(
            id: definition.trophyId,
            groupId: definition.trophyGroupId ?? "default",
            type: definition.trophyType,
            name: definition.trophyName ?? "",
            detail: definition.trophyDetail ?? "",
            iconURL: definition.trophyIconUrl.flatMap(URL.init(string:)),
            isHidden: definition.trophyHidden,
            isEarned: earning?.earned ?? false,
            earnedAt: earning?.earnedDateTime,
            earnedRate: earning?.trophyEarnedRate.flatMap { Double($0) },
            rarity: earning?.trophyRare,
            progress: progress
        )
    }
}

/// A PS5 trophy that counts towards a target: "37 of 50".
public struct TrophyProgress: Sendable, Hashable {
    public let current: Int
    public let target: Int
    public let updatedAt: Date?

    public init(current: Int, target: Int, updatedAt: Date?) {
        self.current = current
        self.target = target
        self.updatedAt = updatedAt
    }

    public var fraction: Double {
        target > 0 ? min(1, Double(current) / Double(target)) : 0
    }
}

// MARK: - Profile

/// The person's trophy level and totals.
public struct TrophySummary: Decodable, Sendable, Hashable {
    public let accountId: String
    /// The level as text (`"412"`), as PSN sends it.
    public let trophyLevel: String
    /// Percent towards the next level.
    public let progress: Int
    /// 1–10: the colour of the level's badge.
    public let tier: Int
    public let earnedTrophies: TrophyCounts

    public var level: Int { Int(trophyLevel) ?? 0 }
}

public struct PSNProfile: Decodable, Sendable, Hashable {
    public struct Avatar: Decodable, Sendable, Hashable {
        public let size: String
        public let url: String
    }

    public let onlineId: String
    public let avatars: [Avatar]?
    public let isPlus: Bool?

    /// The largest avatar.
    public var avatarURL: URL? {
        let order = ["xl", "l", "m", "s"]
        let best = avatars?.min { (order.firstIndex(of: $0.size) ?? 9) < (order.firstIndex(of: $1.size) ?? 9) }
        return best.flatMap { URL(string: $0.url) }
    }
}

// MARK: - Time played

/// A game in the person's game list, with the time played (PS4 and PS5 only).
public struct PlayedGame: Decodable, Sendable, Hashable, Identifiable {
    /// `PPSA01234_00`: the game's title id, not its trophy list's.
    public let titleId: String
    public let name: String
    public let localizedName: String?
    public let imageUrl: String?
    public let localizedImageUrl: String?
    /// `ps5_native_game`, `ps4_game`…
    public let category: String?
    public let playCount: Int?
    public let firstPlayedDateTime: Date?
    public let lastPlayedDateTime: Date?
    /// `PT228H56M33S`.
    public let playDuration: String?

    public var id: String { titleId }
    public var displayName: String { localizedName ?? name }
    public var imageURL: URL? { (localizedImageUrl ?? imageUrl).flatMap(URL.init(string:)) }
    public var timePlayed: TimeInterval? { playDuration.flatMap(PSNDuration.parse) }
}

struct PlayedGamesPage: Decodable, PSNPage {
    let titles: [PlayedGame]
    let totalItemCount: Int
    let nextOffset: Int?

    var items: [PlayedGame] { titles }
}

/// Which trophy lists a game title (`PPSA…`) has: the bridge from time played to trophies.
public struct TitleTrophyLink: Decodable, Sendable, Hashable {
    public struct List: Decodable, Sendable, Hashable {
        public let npCommunicationId: String
    }

    public let npTitleId: String
    public let trophyTitles: [List]
}

struct TitleTrophyLinksResponse: Decodable {
    let titles: [TitleTrophyLink]
}

// MARK: - Presence

/// What the person is doing on PSN right now.
public struct Presence: Decodable, Sendable, Hashable {
    public struct RunningGame: Decodable, Sendable, Hashable {
        public let npTitleId: String
        public let titleName: String
        public let format: String?
        public let launchPlatform: String?
        public let npTitleIconUrl: String?
        public let conceptIconUrl: String?

        public var iconURL: URL? { (conceptIconUrl ?? npTitleIconUrl).flatMap(URL.init(string:)) }
    }

    public let availability: String?
    public let onlineStatus: String?
    public let platform: String?
    public let gameTitleInfoList: [RunningGame]?

    /// The game running on the console, if any.
    public var runningGame: RunningGame? { gameTitleInfoList?.first }
}

struct PresenceResponse: Decodable {
    struct Basic: Decodable {
        struct PrimaryPlatformInfo: Decodable {
            let onlineStatus: String?
            let platform: String?
        }

        let availability: String?
        let primaryPlatformInfo: PrimaryPlatformInfo?
        let gameTitleInfoList: [Presence.RunningGame]?
    }

    let basicPresence: Basic

    var presence: Presence {
        Presence(
            availability: basicPresence.availability,
            onlineStatus: basicPresence.primaryPlatformInfo?.onlineStatus,
            platform: basicPresence.primaryPlatformInfo?.platform,
            gameTitleInfoList: basicPresence.gameTitleInfoList
        )
    }
}

// MARK: - Paging

/// A page of a list PSN returns in parts (`limit`, `offset`, `nextOffset`).
protocol PSNPage: Decodable {
    associatedtype Item
    var items: [Item] { get }
    var totalItemCount: Int { get }
    var nextOffset: Int? { get }
}
