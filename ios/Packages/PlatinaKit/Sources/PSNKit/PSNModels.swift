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
    public init(
        npCommunicationId: String,
        npServiceName: String = "trophy2",
        trophySetVersion: String = "01.00",
        trophyTitleName: String,
        trophyTitleIconUrl: String? = nil,
        trophyTitlePlatform: String = "PS5",
        trophyTitleDetail: String? = nil,
        hasTrophyGroups: Bool = false,
        definedTrophies: TrophyCounts,
        earnedTrophies: TrophyCounts,
        progress: Int,
        hiddenFlag: Bool? = false,
        lastUpdatedDateTime: Date
    ) {
        self.npCommunicationId = npCommunicationId
        self.npServiceName = npServiceName
        self.trophySetVersion = trophySetVersion
        self.trophyTitleName = trophyTitleName
        self.trophyTitleIconUrl = trophyTitleIconUrl
        self.trophyTitlePlatform = trophyTitlePlatform
        self.trophyTitleDetail = trophyTitleDetail
        self.hasTrophyGroups = hasTrophyGroups
        self.definedTrophies = definedTrophies
        self.earnedTrophies = earnedTrophies
        self.progress = progress
        self.hiddenFlag = hiddenFlag
        self.lastUpdatedDateTime = lastUpdatedDateTime
    }

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
    public var iconURL: URL? { PSNImageURL.from(trophyTitleIconUrl) }
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
    public init(trophyGroupId: String, trophyGroupName: String, trophyGroupDetail: String? = nil, trophyGroupIconUrl: String? = nil, definedTrophies: TrophyCounts) {
        self.trophyGroupId = trophyGroupId
        self.trophyGroupName = trophyGroupName
        self.trophyGroupDetail = trophyGroupDetail
        self.trophyGroupIconUrl = trophyGroupIconUrl
        self.definedTrophies = definedTrophies
    }

    /// `default` for the base game, `001`, `002`… for each DLC.
    public let trophyGroupId: String
    public let trophyGroupName: String
    public let trophyGroupDetail: String?
    public let trophyGroupIconUrl: String?
    public let definedTrophies: TrophyCounts

    public var id: String { trophyGroupId }
    public var isBaseGame: Bool { trophyGroupId == "default" }
    public var iconURL: URL? { PSNImageURL.from(trophyGroupIconUrl) }
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
public struct TrophyEarning: Decodable, Sendable, Hashable {
    public let trophyId: Int
    public let earned: Bool
    public let earnedDateTime: Date?
    public let trophyRare: TrophyRarity?
    /// A percentage as text: `"12.3"`.
    public let trophyEarnedRate: String?
    /// PS5 progress trophies: how far along (`"37"` of a target of `"50"`).
    public let progress: String?
    public let progressRate: Int?
    public let progressedDateTime: Date?

    public init(trophyId: Int, earned: Bool, earnedDateTime: Date? = nil, trophyRare: TrophyRarity? = nil, trophyEarnedRate: String? = nil, progress: String? = nil, progressRate: Int? = nil, progressedDateTime: Date? = nil) {
        self.trophyId = trophyId
        self.earned = earned
        self.earnedDateTime = earnedDateTime
        self.trophyRare = trophyRare
        self.trophyEarnedRate = trophyEarnedRate
        self.progress = progress
        self.progressRate = progressRate
        self.progressedDateTime = progressedDateTime
    }

    public var earnedRate: Double? { trophyEarnedRate.flatMap { Double($0) } }
    public var progressCurrent: Int? { progress.flatMap { Int($0) } }
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
            iconURL: PSNImageURL.from(definition.trophyIconUrl),
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

// MARK: - A game's progress

/// The person's progress in one trophy list, without its trophies: one cheap request that says
/// whether anything changed (a session asks it every couple of minutes).
public struct TitleProgress: Decodable, Sendable, Hashable {
    public struct Group: Decodable, Sendable, Hashable {
        public let trophyGroupId: String
        public let progress: Int
        public let earnedTrophies: TrophyCounts
        public let lastUpdatedDateTime: Date?
    }

    public let trophySetVersion: String
    public let progress: Int
    public let earnedTrophies: TrophyCounts
    public let lastUpdatedDateTime: Date
    public let trophyGroups: [Group]?

    public init(trophySetVersion: String, progress: Int, earnedTrophies: TrophyCounts, lastUpdatedDateTime: Date, trophyGroups: [Group]? = nil) {
        self.trophySetVersion = trophySetVersion
        self.progress = progress
        self.earnedTrophies = earnedTrophies
        self.lastUpdatedDateTime = lastUpdatedDateTime
        self.trophyGroups = trophyGroups
    }
}

// MARK: - Profile

/// The person's trophy level and totals.
public struct TrophySummary: Decodable, Sendable, Hashable {
    public init(accountId: String, level: Int, progress: Int, tier: Int, earnedTrophies: TrophyCounts) {
        self.accountId = accountId
        self.level = level
        self.progress = progress
        self.tier = tier
        self.earnedTrophies = earnedTrophies
    }

    public let accountId: String
    /// The trophy level: `trophyLevel` in PSN's answer.
    public let level: Int
    /// Percent towards the next level.
    public let progress: Int
    /// 1–10: the colour of the level's badge.
    public let tier: Int
    public let earnedTrophies: TrophyCounts

    enum CodingKeys: String, CodingKey {
        case accountId, trophyLevel, progress, tier, earnedTrophies
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try container.decode(String.self, forKey: .accountId)
        // A number (`437`) in PSN's answers; psn-api's model has it as text (`"437"`).
        if let number = try? container.decode(Int.self, forKey: .trophyLevel) {
            level = number
        } else {
            let text = try container.decode(String.self, forKey: .trophyLevel)
            guard let number = Int(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .trophyLevel, in: container, debugDescription: "Not a level: \(text)"
                )
            }
            level = number
        }
        progress = try container.decode(Int.self, forKey: .progress)
        tier = try container.decode(Int.self, forKey: .tier)
        earnedTrophies = try container.decode(TrophyCounts.self, forKey: .earnedTrophies)
    }
}

public struct PSNProfile: Decodable, Sendable, Hashable {
    public struct Avatar: Decodable, Sendable, Hashable {
        public init(size: String, url: String) {
            self.size = size
            self.url = url
        }

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
        return PSNImageURL.from(best?.url)
    }
}

// MARK: - Time played

/// A game in the person's game list, with the time played (PS4 and PS5 only).
public struct PlayedGame: Decodable, Sendable, Hashable, Identifiable {
    public init(
        titleId: String,
        name: String,
        localizedName: String? = nil,
        imageUrl: String? = nil,
        localizedImageUrl: String? = nil,
        category: String? = "ps5_native_game",
        playCount: Int? = nil,
        firstPlayedDateTime: Date? = nil,
        lastPlayedDateTime: Date? = nil,
        playDuration: String? = nil,
        concept: Concept? = nil
    ) {
        self.titleId = titleId
        self.name = name
        self.localizedName = localizedName
        self.imageUrl = imageUrl
        self.localizedImageUrl = localizedImageUrl
        self.category = category
        self.playCount = playCount
        self.firstPlayedDateTime = firstPlayedDateTime
        self.lastPlayedDateTime = lastPlayedDateTime
        self.playDuration = playDuration
        self.concept = concept
    }

    /// The game as the PlayStation Store knows it, with its art.
    public struct Concept: Decodable, Sendable, Hashable {
        public struct Media: Decodable, Sendable, Hashable {
            public init(images: [PSNGameArt]?) {
                self.images = images
            }

            public let images: [PSNGameArt]?
        }

        public init(media: Media?) {
            self.media = media
        }

        public let media: Media?
    }

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
    /// The store's art of the game (`concept.media.images`): its cover, logo, backgrounds.
    public let concept: Concept?

    public var id: String { titleId }
    public var displayName: String { localizedName ?? name }
    public var imageURL: URL? { PSNImageURL.from((localizedImageUrl ?? imageUrl)) }
    public var timePlayed: TimeInterval? { playDuration.flatMap(PSNDuration.parse) }
    public var art: [PSNGameArt] { concept?.media?.images ?? [] }
    /// The art for the top of the game's screen: the PS5 game hub's cover (no title on it), else
    /// a background, else the store's poster.
    public var keyArtURL: URL? { PSNGameArt.url(in: art, PSNGameArt.keyArtTypes) }
    /// The game's title as a picture (transparent PNG), for over the key art.
    public var logoURL: URL? { PSNGameArt.url(in: art, [PSNGameArt.logo]) }
}

/// A picture of a game from the PlayStation Store (a concept's media), by its type.
public struct PSNGameArt: Decodable, Sendable, Hashable {
    public init(url: String?, type: String?) {
        self.url = url
        self.type = type
    }

    public let url: String?
    /// `GAMEHUB_COVER_ART`, `LOGO`, `PORTRAIT_BANNER`, `SCREENSHOT`…
    public let type: String?

    public var imageURL: URL? { PSNImageURL.from(url) }

    /// 16:9 key art of the PS5 game hub, without the title: the console lays the logo over it.
    public static let gameHubCoverArt = "GAMEHUB_COVER_ART"
    /// 16:9 backgrounds of the game hub and the store.
    public static let backgroundLayerArt = "BACKGROUND_LAYER_ART"
    public static let background = "BACKGROUND"
    /// 2:3 poster of the store, the title usually drawn on it.
    public static let portraitBanner = "PORTRAIT_BANNER"
    /// The title, transparent PNG.
    public static let logo = "LOGO"
    /// The key art for a header, best first.
    public static let keyArtTypes = [gameHubCoverArt, backgroundLayerArt, background, portraitBanner]

    /// The first picture of the first of `types` that the game has.
    public static func url(in art: [PSNGameArt], _ types: [String]) -> URL? {
        for type in types {
            if let url = art.lazy.filter({ $0.type == type }).compactMap(\.imageURL).first { return url }
        }
        return nil
    }
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
        public init(npCommunicationId: String) {
            self.npCommunicationId = npCommunicationId
        }

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

        public var iconURL: URL? { PSNImageURL.from((conceptIconUrl ?? npTitleIconUrl)) }
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
