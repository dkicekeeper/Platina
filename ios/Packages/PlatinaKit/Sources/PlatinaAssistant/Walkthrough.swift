import Foundation

// The walkthrough "by the hand" (docs/assistant.md §8, docs/PLAN.md §5): a game's chapters, built
// once on the server and kept there for everyone, then each chapter's steps when the player
// gets there. Here: the wire format, the requests, and where the player is (pure logic, so it is
// tested on Linux too).

/// A game's walkthrough plan: its chapters in order, what each can lose, the cleanup.
public struct Walkthrough: Codable, Sendable, Equatable {
    public struct Missable: Codable, Sendable, Equatable {
        /// The trophy that can be missed, or nil for an item or a collectible that feeds one.
        public let trophyId: Int?
        public let note: String

        public init(trophyId: Int?, note: String) {
            self.trophyId = trophyId
            self.note = note
        }
    }

    public struct Collectibles: Codable, Sendable, Equatable {
        public let kind: String
        public let count: Int

        public init(kind: String, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public struct Chapter: Codable, Sendable, Equatable, Identifiable {
        /// `c1`, `c2`… in the order of play.
        public let id: String
        public let title: String
        /// One or two sentences, no story spoilers.
        public let summary: String
        public let missable: [Missable]
        public let choices: [String]
        public let collectibles: [Collectibles]
        public let trophyIds: [Int]
        /// The story trophy for finishing the chapter: earned, the chapter is done.
        public let completionTrophyId: Int?
        /// 1 for the first playthrough, 2 for the second…
        public let playthrough: Int
        public let sourceIds: [String]

        public init(
            id: String, title: String, summary: String, missable: [Missable] = [], choices: [String] = [],
            collectibles: [Collectibles] = [], trophyIds: [Int] = [], completionTrophyId: Int? = nil,
            playthrough: Int = 1, sourceIds: [String] = []
        ) {
            self.id = id
            self.title = title
            self.summary = summary
            self.missable = missable
            self.choices = choices
            self.collectibles = collectibles
            self.trophyIds = trophyIds
            self.completionTrophyId = completionTrophyId
            self.playthrough = playthrough
            self.sourceIds = sourceIds
        }

        enum CodingKeys: String, CodingKey {
            case id, title, summary, missable, choices, collectibles, trophyIds, completionTrophyId, playthrough, sourceIds
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
            missable = try container.decodeIfPresent([Missable].self, forKey: .missable) ?? []
            choices = try container.decodeIfPresent([String].self, forKey: .choices) ?? []
            collectibles = try container.decodeIfPresent([Collectibles].self, forKey: .collectibles) ?? []
            trophyIds = try container.decodeIfPresent([Int].self, forKey: .trophyIds) ?? []
            completionTrophyId = try container.decodeIfPresent(Int.self, forKey: .completionTrophyId)
            playthrough = try container.decodeIfPresent(Int.self, forKey: .playthrough) ?? 1
            sourceIds = try container.decodeIfPresent([String].self, forKey: .sourceIds) ?? []
        }

        /// Something here can be lost for good: a missable thing or a choice.
        public var hasWarnings: Bool { !missable.isEmpty || !choices.isEmpty }
    }

    public let gameId: String
    public let language: String
    public let generatedAt: String
    /// Two to four sentences: how the route to the platinum goes.
    public let overview: String
    public let playthroughs: Int?
    public let chapters: [Chapter]
    /// Markdown: what is left after the story.
    public let cleanup: String
    public let sources: [Guide.Source]

    public init(
        gameId: String, language: String, generatedAt: String, overview: String, playthroughs: Int?,
        chapters: [Chapter], cleanup: String, sources: [Guide.Source]
    ) {
        self.gameId = gameId
        self.language = language
        self.generatedAt = generatedAt
        self.overview = overview
        self.playthroughs = playthroughs
        self.chapters = chapters
        self.cleanup = cleanup
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case gameId, language, generatedAt, overview, playthroughs, chapters, cleanup, sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try container.decode(String.self, forKey: .gameId)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "ru"
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        overview = try container.decodeIfPresent(String.self, forKey: .overview) ?? ""
        playthroughs = try container.decodeIfPresent(Int.self, forKey: .playthroughs)
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
        cleanup = try container.decodeIfPresent(String.self, forKey: .cleanup) ?? ""
        sources = try container.decodeIfPresent([Guide.Source].self, forKey: .sources) ?? []
    }

    public func chapter(_ id: String) -> Chapter? { chapters.first { $0.id == id } }
    public func sources(of chapter: Chapter) -> [Guide.Source] {
        chapter.sourceIds.compactMap { id in sources.first { $0.id == id } }
    }
}

/// One chapter's steps, in the order of play.
public struct ChapterSteps: Codable, Sendable, Equatable {
    public struct Step: Codable, Sendable, Equatable, Identifiable {
        public enum Kind: String, Codable, Sendable, CaseIterable {
            case path
            case collectible
            case choice
            case pointOfNoReturn = "point_of_no_return"
            case trophy
            case boss
            case tip

            /// A kind a newer server sends reads as a tip.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                self = Kind(rawValue: raw) ?? .tip
            }

            /// Losing it costs a trophy: the step is a warning, not just a direction.
            public var isWarning: Bool { self == .choice || self == .pointOfNoReturn }
        }

        public struct Collectible: Codable, Sendable, Equatable {
            public let kind: String
            public let number: Int

            public init(kind: String, number: Int) {
                self.kind = kind
                self.number = number
            }
        }

        /// A picture of the spot on its source's site: loaded from there, shown with the source.
        public struct Image: Codable, Sendable, Equatable {
            public let url: String
            public let sourceId: String?

            public init(url: String, sourceId: String?) {
                self.url = url
                self.sourceId = sourceId
            }
        }

        public struct Video: Codable, Sendable, Equatable {
            public let youtubeId: String
            public let startSeconds: Int

            public init(youtubeId: String, startSeconds: Int) {
                self.youtubeId = youtubeId
                self.startSeconds = startSeconds
            }

            public var url: URL? {
                URL(string: "https://www.youtube.com/watch?v=\(youtubeId)&t=\(startSeconds)s")
            }
        }

        /// `s1`, `s2`… in order.
        public let id: String
        public let kind: Kind
        /// Markdown, one to three sentences.
        public let text: String
        public let trophyIds: [Int]
        /// Reveals the story or a hidden trophy: shown on a tap.
        public let spoiler: Bool
        public let collectible: Collectible?
        public let sourceId: String?
        public let image: Image?
        public let video: Video?

        public init(
            id: String, kind: Kind, text: String, trophyIds: [Int] = [], spoiler: Bool = false,
            collectible: Collectible? = nil, sourceId: String? = nil, image: Image? = nil, video: Video? = nil
        ) {
            self.id = id
            self.kind = kind
            self.text = text
            self.trophyIds = trophyIds
            self.spoiler = spoiler
            self.collectible = collectible
            self.sourceId = sourceId
            self.image = image
            self.video = video
        }

        enum CodingKeys: String, CodingKey {
            case id, kind, text, trophyIds, spoiler, collectible, sourceId, image, video
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .tip
            text = try container.decode(String.self, forKey: .text)
            trophyIds = try container.decodeIfPresent([Int].self, forKey: .trophyIds) ?? []
            spoiler = try container.decodeIfPresent(Bool.self, forKey: .spoiler) ?? false
            collectible = try container.decodeIfPresent(Collectible.self, forKey: .collectible)
            sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
            image = try container.decodeIfPresent(Image.self, forKey: .image)
            video = try container.decodeIfPresent(Video.self, forKey: .video)
        }
    }

    public let gameId: String
    public let language: String
    public let chapterId: String
    /// The plan the steps were built against: a newer plan makes them stale.
    public let walkthroughGeneratedAt: String
    public let generatedAt: String
    public let steps: [Step]
    public let sources: [Guide.Source]

    public init(
        gameId: String, language: String, chapterId: String, walkthroughGeneratedAt: String, generatedAt: String,
        steps: [Step], sources: [Guide.Source]
    ) {
        self.gameId = gameId
        self.language = language
        self.chapterId = chapterId
        self.walkthroughGeneratedAt = walkthroughGeneratedAt
        self.generatedAt = generatedAt
        self.steps = steps
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case gameId, language, chapterId, walkthroughGeneratedAt, generatedAt, steps, sources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try container.decode(String.self, forKey: .gameId)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "ru"
        chapterId = try container.decode(String.self, forKey: .chapterId)
        walkthroughGeneratedAt = try container.decodeIfPresent(String.self, forKey: .walkthroughGeneratedAt) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        steps = try container.decodeIfPresent([Step].self, forKey: .steps) ?? []
        sources = try container.decodeIfPresent([Guide.Source].self, forKey: .sources) ?? []
    }

    public func source(_ id: String?) -> Guide.Source? {
        guard let id else { return nil }
        return sources.first { $0.id == id }
    }
}

// MARK: - Requests and events

/// What the app sends to build a chapter's steps: the guide request's game, and the chapter.
public struct ChapterRequest: Sendable, Encodable {
    public let `protocol`: Int
    public let language: String
    public let refresh: Bool
    public let game: GuideRequest.Game
    public let chapterId: String

    public init(language: String, refresh: Bool, game: GuideRequest.Game, chapterId: String) {
        self.protocol = AssistantProtocol.version
        self.language = language
        self.refresh = refresh
        self.game = game
        self.chapterId = chapterId
    }
}

public enum WalkthroughStreamEvent: Sendable, Equatable {
    /// `search`, `reading`, `writing`.
    case progress(step: String)
    case walkthrough(Walkthrough)
    case chapter(ChapterSteps)
    /// `no_walkthrough`: the plan is needed first.
    case error(code: String, retryable: Bool)
}

public extension WalkthroughStreamEvent {
    init?(_ event: SSEParser.Event) {
        struct Step: Decodable { let step: String }
        struct Failure: Decodable { let code: String?; let retryable: Bool? }
        let bytes = Data(event.data.utf8)
        let decoder = JSONDecoder()
        switch event.name {
        case "progress":
            guard let payload = try? decoder.decode(Step.self, from: bytes) else { return nil }
            self = .progress(step: payload.step)
        case "walkthrough":
            guard let walkthrough = try? decoder.decode(Walkthrough.self, from: bytes) else {
                self = .error(code: "invalid", retryable: true)
                return
            }
            self = .walkthrough(walkthrough)
        case "chapter":
            guard let chapter = try? decoder.decode(ChapterSteps.self, from: bytes) else {
                self = .error(code: "invalid", retryable: true)
                return
            }
            self = .chapter(chapter)
        case "error":
            let payload = try? decoder.decode(Failure.self, from: bytes)
            self = .error(code: payload?.code ?? "internal", retryable: payload?.retryable ?? false)
        default:
            return nil
        }
    }
}

/// The server's walkthrough endpoints (docs/assistant.md §8).
public protocol WalkthroughTransport: Sendable {
    func walkthrough(_ request: GuideRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error>
    func chapter(_ request: ChapterRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error>
    func cachedWalkthrough(gameId: String, language: String) async throws -> Walkthrough?
    func cachedChapter(gameId: String, language: String, chapterId: String) async throws -> ChapterSteps?
}

// MARK: - Where the player is

/// What the player has done of a walkthrough: their own data, kept on the phone (and iCloud).
public struct WalkthroughMarks: Sendable, Equatable {
    /// Steps ticked by hand, as `c2/s5`.
    public var checkedSteps: Set<String>
    /// Chapters marked done by hand.
    public var doneChapters: Set<String>
    /// The chapter the player said they are on; nil: worked out from the rest.
    public var currentChapter: String?

    public init(checkedSteps: Set<String> = [], doneChapters: Set<String> = [], currentChapter: String? = nil) {
        self.checkedSteps = checkedSteps
        self.doneChapters = doneChapters
        self.currentChapter = currentChapter
    }

    public static func stepKey(chapterId: String, stepId: String) -> String { "\(chapterId)/\(stepId)" }
}

/// Where the player is in a walkthrough: which chapters are behind, which one is now.
public struct WalkthroughPosition: Sendable, Equatable {
    public enum ChapterState: String, Sendable, Equatable {
        case done
        case current
        case ahead
    }

    public let states: [String: ChapterState]
    /// The chapter to play now; nil when every chapter is done (the cleanup is left).
    public let currentChapterId: String?

    public init(walkthrough: Walkthrough, earned: Set<Int>, marks: WalkthroughMarks) {
        let chapters = walkthrough.chapters
        var states: [String: ChapterState] = [:]
        var current: String?
        if let chosen = marks.currentChapter, let index = chapters.firstIndex(where: { $0.id == chosen }) {
            // The player's word goes: before it is behind, after it ahead, unless marked done.
            for (i, chapter) in chapters.enumerated() {
                if i == index {
                    states[chapter.id] = .current
                } else if i < index || marks.doneChapters.contains(chapter.id) {
                    states[chapter.id] = .done
                } else {
                    states[chapter.id] = .ahead
                }
            }
            current = chosen
        } else {
            // A chapter is behind when marked done or its completion trophy is earned, and so is
            // every chapter before one that is: the story only goes forward. A completion trophy
            // an earlier chapter already has (a second playthrough's) counts for the first only.
            var seenTrophies = Set<Int>()
            var lastBehind = -1
            for (index, chapter) in chapters.enumerated() {
                var finished = marks.doneChapters.contains(chapter.id)
                if let trophy = chapter.completionTrophyId, !seenTrophies.contains(trophy) {
                    seenTrophies.insert(trophy)
                    if earned.contains(trophy) { finished = true }
                }
                if finished { lastBehind = index }
            }
            for (i, chapter) in chapters.enumerated() {
                if i <= lastBehind || marks.doneChapters.contains(chapter.id) {
                    states[chapter.id] = .done
                } else if current == nil {
                    states[chapter.id] = .current
                    current = chapter.id
                } else {
                    states[chapter.id] = .ahead
                }
            }
        }
        self.states = states
        self.currentChapterId = current
    }

    public func state(of chapterId: String) -> ChapterState { states[chapterId] ?? .ahead }

    /// A step is done when ticked, when its chapter is behind, or when every trophy it earns is
    /// earned (a collectible's trophy earned means every collectible of it is found).
    public static func isStepDone(
        _ step: ChapterSteps.Step, chapterId: String, earned: Set<Int>, marks: WalkthroughMarks, chapterState: ChapterState
    ) -> Bool {
        if marks.checkedSteps.contains(WalkthroughMarks.stepKey(chapterId: chapterId, stepId: step.id)) { return true }
        if chapterState == .done { return true }
        return !step.trophyIds.isEmpty && step.trophyIds.allSatisfy(earned.contains)
    }

    /// The first step of a chapter not done yet.
    public static func nextStep(
        in chapter: ChapterSteps, earned: Set<Int>, marks: WalkthroughMarks, chapterState: ChapterState
    ) -> ChapterSteps.Step? {
        chapter.steps.first { !isStepDone($0, chapterId: chapter.chapterId, earned: earned, marks: marks, chapterState: chapterState) }
    }
}
