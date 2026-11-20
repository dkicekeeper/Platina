import Foundation

/// A game's guide (docs/assistant.md §4): built once on the server from Stratege.ru and the web,
/// kept there for everyone and here for this person.
public struct Guide: Codable, Sendable, Equatable {
    public struct Summary: Codable, Sendable, Equatable {
        /// 1–10.
        public let difficulty: Int?
        public let hoursMin: Double?
        public let hoursMax: Double?
        public let playthroughs: Int?
        public let onlineTrophies: Int?
        public let missableTrophies: Int?
        public let glitchedTrophies: Int?
        public let difficultyAffects: Bool?
        /// Two to four sentences: what the platinum is like and how to go for it.
        public let overview: String?

        public init(
            difficulty: Int?, hoursMin: Double?, hoursMax: Double?, playthroughs: Int?, onlineTrophies: Int?,
            missableTrophies: Int?, glitchedTrophies: Int?, difficultyAffects: Bool?, overview: String?
        ) {
            self.difficulty = difficulty
            self.hoursMin = hoursMin
            self.hoursMax = hoursMax
            self.playthroughs = playthroughs
            self.onlineTrophies = onlineTrophies
            self.missableTrophies = missableTrophies
            self.glitchedTrophies = glitchedTrophies
            self.difficultyAffects = difficultyAffects
            self.overview = overview
        }
    }

    /// A step of the road map: "Step 1. The story without missing X".
    public struct Step: Codable, Sendable, Equatable, Identifiable {
        public let title: String
        /// Markdown.
        public let text: String
        public let trophyIds: [Int]

        public var id: String { title }

        public init(title: String, text: String, trophyIds: [Int]) {
            self.title = title
            self.text = text
            self.trophyIds = trophyIds
        }
    }

    public struct Missable: Codable, Sendable, Equatable {
        public let trophyId: Int
        /// When and why it can be missed.
        public let note: String

        public init(trophyId: Int, note: String) {
            self.trophyId = trophyId
            self.note = note
        }
    }

    public struct Tip: Codable, Sendable, Equatable {
        public let trophyId: Int
        /// Markdown, one to five sentences.
        public let text: String
        public let sourceIds: [String]

        public init(trophyId: Int, text: String, sourceIds: [String]) {
            self.trophyId = trophyId
            self.text = text
            self.sourceIds = sourceIds
        }
    }

    public struct Source: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let url: String

        public init(id: String, title: String, url: String) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    public struct Stratege: Codable, Sendable, Equatable {
        public let url: String?
        public let averagePlatinumHours: Double?
        public let platinumPercent: Double?
    }

    public let gameId: String
    public let language: String
    public let generatedAt: String?
    public let summary: Summary
    public let steps: [Step]
    public let missable: [Missable]
    public let tips: [Tip]
    public let sources: [Source]
    public let stratege: Stratege?

    public init(
        gameId: String, language: String, generatedAt: String?, summary: Summary, steps: [Step],
        missable: [Missable], tips: [Tip], sources: [Source], stratege: Stratege?
    ) {
        self.gameId = gameId
        self.language = language
        self.generatedAt = generatedAt
        self.summary = summary
        self.steps = steps
        self.missable = missable
        self.tips = tips
        self.sources = sources
        self.stratege = stratege
    }

    enum CodingKeys: String, CodingKey {
        case gameId, language, generatedAt, summary, steps, missable, tips, sources, stratege
    }

    /// Lenient: a guide with a missing list still reads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try container.decode(String.self, forKey: .gameId)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "ru"
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
        summary = try container.decode(Summary.self, forKey: .summary)
        steps = try container.decodeIfPresent([Step].self, forKey: .steps) ?? []
        missable = try container.decodeIfPresent([Missable].self, forKey: .missable) ?? []
        tips = try container.decodeIfPresent([Tip].self, forKey: .tips) ?? []
        sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
        stratege = try container.decodeIfPresent(Stratege.self, forKey: .stratege)
    }

    public func tip(for trophyId: Int) -> Tip? { tips.first { $0.trophyId == trophyId } }
    public func missable(for trophyId: Int) -> Missable? { missable.first { $0.trophyId == trophyId } }
    public func sources(of tip: Tip) -> [Source] { tip.sourceIds.compactMap { id in sources.first { $0.id == id } } }
}

/// What the app sends to build a guide.
public struct GuideRequest: Sendable, Encodable {
    public struct Game: Sendable, Encodable {
        public struct Trophy: Sendable, Encodable {
            public let id: Int
            public let name: String
            public let detail: String
            public let type: String
            public let hidden: Bool
            public let groupId: String

            public init(id: Int, name: String, detail: String, type: String, hidden: Bool, groupId: String) {
                self.id = id
                self.name = name
                self.detail = detail
                self.type = type
                self.hidden = hidden
                self.groupId = groupId
            }
        }

        public let npCommunicationId: String
        public let name: String
        public let platform: String
        public let trophySetVersion: String
        public let trophies: [Trophy]

        public init(npCommunicationId: String, name: String, platform: String, trophySetVersion: String, trophies: [Trophy]) {
            self.npCommunicationId = npCommunicationId
            self.name = name
            self.platform = platform
            self.trophySetVersion = trophySetVersion
            self.trophies = trophies
        }
    }

    public let `protocol`: Int
    public let language: String
    public let refresh: Bool
    public let game: Game

    public init(language: String, refresh: Bool, game: Game) {
        self.protocol = AssistantProtocol.version
        self.language = language
        self.refresh = refresh
        self.game = game
    }
}
