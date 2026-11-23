#if canImport(SwiftData)
import Foundation
import PSNKit
import PlatinaCore
import PlatinaAssistant

/// Plati's tools on the phone (docs/assistant.md §5): it reads the person's real data instead of
/// guessing, and changes only what the person would change themselves (goals, a status, a note,
/// a session's summary).
@MainActor
public final class AssistantToolkit: AssistantToolExecuting {
    private let store: LibraryStore
    private let sessions: SessionTracker
    private let guides: GuideService
    private let gameHelp: GameHelpService?
    private let walkthroughs: WalkthroughService?
    private let now: () -> Date

    public init(
        store: LibraryStore,
        sessions: SessionTracker,
        guides: GuideService,
        gameHelp: GameHelpService? = nil,
        walkthroughs: WalkthroughService? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.gameHelp = gameHelp
        self.walkthroughs = walkthroughs
        self.store = store
        self.sessions = sessions
        self.guides = guides
        self.now = now
    }

    public func execute(name: String, input: JSONValue) async -> AssistantToolOutput {
        guard let tool = AssistantProtocol.Tool(rawValue: name) else {
            return .failure("Unknown tool \(name)")
        }
        do {
            switch tool {
            case .getProfile: return try encode(profile())
            case .listGames: return try encode(listGames(input))
            case .getGame: return try encode(game(input))
            case .listTrophies: return try encode(listTrophies(input))
            case .getGuide: return try await getGuide(input)
            case .getGameHelp: return try encode(try await getGameHelp(input))
            case .getWalkthrough: return try encode(try await getWalkthrough(input))
            case .getChapter: return try encode(try await getChapter(input))
            case .setWalkthroughProgress: return try encode(try setWalkthroughProgress(input))
            case .getSessions: return try encode(listSessions(input))
            case .getCurrentSession: return try encode(currentSession())
            case .setSessionGoals: return try encode(setGoals(input))
            case .setGameStatus: return try encode(setStatus(input))
            case .saveNote: return try encode(saveNote(input))
            case .saveSessionSummary: return try encode(saveSummary(input))
            }
        } catch let error as ToolError {
            return .failure(error.message)
        } catch {
            return .failure("Failed: \(error)")
        }
    }

    // MARK: Reading

    private struct Counts: Encodable {
        let platinum, gold, silver, bronze: Int
        init(_ counts: TrophyCounts) {
            platinum = counts.platinum
            gold = counts.gold
            silver = counts.silver
            bronze = counts.bronze
        }
    }

    private struct Profile: Encodable {
        let online_id: String?
        let level: Int?
        let level_progress_percent: Int?
        let ps5_games: Int
        let platinums: Int
        let games_at_100_percent: Int
        let trophies: Counts
        let hours_played: Int
    }

    private func profile() throws -> Profile {
        let profile = try store.profile()
        let summaries = try summaries()
        let stats = StatsCalculator.compute(games: summaries, trophies: [])
        return Profile(
            online_id: profile?.onlineId,
            level: profile?.level,
            level_progress_percent: profile?.levelProgress,
            ps5_games: stats.gameCount,
            platinums: stats.platinumCount,
            games_at_100_percent: stats.completedCount,
            trophies: Counts(stats.earned),
            hours_played: Int(stats.totalPlayTime / 3600)
        )
    }

    private struct GameLine: Encodable {
        let id: String
        let name: String
        let progress_percent: Int
        let earned: Counts
        let total: Counts
        let platinum_earned: Bool
        let hours_played: Double?
        let status: String
        let last_trophy_change: String
        let guide: GuideBrief?
    }

    private struct GuideBrief: Encodable {
        let difficulty: Int?
        let hours_min: Double?
        let hours_max: Double?
    }

    private func listGames(_ input: JSONValue) throws -> [GameLine] {
        let filter = input["filter"]?.stringValue ?? "all"
        let limit = min(Int(input["limit"]?.numberValue ?? 20), 100)
        let plans = try store.plans()
        let games = try store.games()
        let byId = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let summaries = games.map { $0.summary(status: plans[$0.id] ?? .none) }
        let picked: [GameSummary]
        switch filter {
        case "chasing": picked = summaries.filter { $0.status == .chasing }.filtered(shelf: .all, sort: .recent)
        case "in_progress": picked = summaries.filtered(shelf: .inProgress, sort: .recent)
        case "platinum": picked = summaries.filtered(shelf: .platinum, sort: .recent)
        case "not_started": picked = summaries.filtered(shelf: .notStarted, sort: .recent)
        case "shelved": picked = summaries.filtered(shelf: .shelved, sort: .recent)
        default: picked = summaries.filtered(shelf: .all, sort: .recent)
        }
        return picked.prefix(limit).compactMap { summary in
            guard let game = byId[summary.id] else { return nil }
            return line(game, status: summary.status)
        }
    }

    private func line(_ game: GameRecord, status: GamePlanStatus) -> GameLine {
        let guide = guides.guide(for: game.id)
        return GameLine(
            id: game.id,
            name: game.name,
            progress_percent: game.progress,
            earned: Counts(game.earned),
            total: Counts(game.defined),
            platinum_earned: game.isPlatinumEarned,
            hours_played: game.playSeconds.map { ($0 / 360).rounded() / 10 },
            status: status.rawValue,
            last_trophy_change: game.lastUpdated.formatted(.iso8601),
            guide: guide.map { GuideBrief(difficulty: $0.summary.difficulty, hours_min: $0.summary.hoursMin, hours_max: $0.summary.hoursMax) }
        )
    }

    private struct GameDetail: Encodable {
        struct Group: Encodable {
            let id: String
            let name: String
            let trophies: Int
        }

        let game: GameLine
        let groups: [Group]
        let last_played: String?
        let launches: Int?
        let note: String?
        let has_guide: Bool
        let guide_summary: Guide.Summary?
        let walkthrough: WalkthroughBrief?
        let sessions_count: Int
    }

    private struct WalkthroughBrief: Encodable {
        let chapters: Int
        let current_chapter: ChapterRef?
    }

    private struct ChapterRef: Encodable {
        let id: String
        let title: String
    }

    private func game(_ input: JSONValue) throws -> GameDetail {
        let game = try requireGame(input)
        let status = try store.plans()[game.id] ?? .none
        let guide = guides.guide(for: game.id)
        return GameDetail(
            game: line(game, status: status),
            groups: game.groups.sorted { $0.groupId < $1.groupId }.map { .init(id: $0.groupId, name: $0.name, trophies: $0.definedTotal) },
            last_played: game.lastPlayed?.formatted(.iso8601),
            launches: game.playCount,
            note: try store.note(gameId: game.id, trophyId: nil)?.text,
            has_guide: guide != nil,
            guide_summary: guide?.summary,
            walkthrough: walkthroughBrief(gameId: game.id),
            sessions_count: try store.sessions(gameId: game.id).count
        )
    }

    private struct TrophyLine: Encodable {
        let id: Int
        let name: String
        let detail: String?
        let type: String
        let hidden: Bool
        let earned: Bool
        let earned_at: String?
        let players_percent: Double?
        let progress: String?
        let group_id: String
        let note: String?
        let missable: String?
    }

    private func listTrophies(_ input: JSONValue) throws -> [TrophyLine] {
        let game = try requireGame(input)
        let filter = input["filter"]?.stringValue ?? "all"
        let type = input["type"]?.stringValue
        let group = input["group_id"]?.stringValue
        let showHidden = input["include_hidden_details"]?.boolValue ?? false
        let limit = min(Int(input["limit"]?.numberValue ?? 60), 200)
        let guide = guides.guide(for: game.id)
        return game.trophies
            .filter { trophy in
                switch filter {
                case "earned": trophy.isEarned
                case "all": true
                default: !trophy.isEarned
                }
            }
            .filter { type == nil || $0.typeRaw == type }
            .filter { group == nil || $0.groupId == group }
            .sorted { $0.trophyId < $1.trophyId }
            .prefix(limit)
            .map { trophy in
                let spoiler = trophy.isHidden && !trophy.isEarned && !showHidden
                return TrophyLine(
                    id: trophy.trophyId,
                    name: spoiler ? "(hidden trophy)" : trophy.name,
                    detail: spoiler ? nil : trophy.detail,
                    type: trophy.typeRaw,
                    hidden: trophy.isHidden,
                    earned: trophy.isEarned,
                    earned_at: trophy.earnedAt?.formatted(.iso8601),
                    players_percent: trophy.earnedRate,
                    progress: trophy.progress.map { "\($0.current)/\($0.target)" },
                    group_id: trophy.groupId,
                    note: try? store.note(gameId: game.id, trophyId: trophy.trophyId)?.text,
                    missable: guide?.missable(for: trophy.trophyId)?.note
                )
            }
    }

    private func getGuide(_ input: JSONValue) async throws -> AssistantToolOutput {
        let game = try requireGame(input)
        guard let guide = await guides.guideBuildingIfNeeded(gameId: game.id) else {
            return .failure("No guide could be built for this game right now.")
        }
        return .success(try JSONValue.encoding(guide))
    }

    private struct SessionLine: Encodable {
        let id: String
        let game_id: String
        let game: String
        let started_at: String
        let minutes: Int
        let paused: Bool
        let progress_from: Int
        let progress_to: Int?
        let trophies_earned: [String]
        let goals: [Goal]?
        let note: String?
        let summary: String?
        let next_steps: String?
    }

    private struct Goal: Encodable {
        let id: Int
        let name: String
        let done: Bool
    }

    private func sessionLine(_ session: PlaySessionRecord, withGoals: Bool) -> SessionLine {
        let game = try? store.game(session.gameId)
        let byId = Dictionary((game?.trophies ?? []).map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        return SessionLine(
            id: session.sessionId,
            game_id: session.gameId,
            game: session.gameName,
            started_at: session.startedAt.formatted(.iso8601),
            minutes: Int(session.elapsed(at: now()) / 60),
            paused: session.isPaused,
            progress_from: session.startProgress,
            progress_to: session.endProgress ?? game?.progress,
            trophies_earned: session.earnedTrophyIds.compactMap { byId[$0]?.name },
            goals: withGoals ? session.goalTrophyIds.map { id in
                Goal(id: id, name: byId[id]?.name ?? "#\(id)", done: session.isGoalDone(id))
            } : nil,
            note: session.note.isEmpty ? nil : session.note,
            summary: session.summary,
            next_steps: session.nextSteps
        )
    }

    private func listSessions(_ input: JSONValue) throws -> [SessionLine] {
        let gameId = input["game_id"]?.stringValue
        let limit = min(Int(input["limit"]?.numberValue ?? 5), 30)
        return try store.sessions(gameId: gameId, limit: limit).map { sessionLine($0, withGoals: true) }
    }

    private struct CurrentSession: Encodable {
        let running: Bool
        let session: SessionLine?
    }

    private func currentSession() throws -> CurrentSession {
        guard let session = sessions.current else { return CurrentSession(running: false, session: nil) }
        return CurrentSession(running: true, session: sessionLine(session, withGoals: true))
    }

    // MARK: Changing

    private struct Done: Encodable {
        let ok: Bool
        let detail: String
    }

    private func setGoals(_ input: JSONValue) throws -> Done {
        let game = try requireGame(input)
        guard let session = sessions.current, session.gameId == game.id else {
            throw ToolError("No session is running in \(game.name). Goals are set for a running session.")
        }
        let known = Set(game.trophies.filter { !$0.isEarned }.map(\.trophyId))
        let ids = (input["trophy_ids"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) }.filter { known.contains($0) }
        guard !ids.isEmpty else { throw ToolError("None of those trophy ids is an unearned trophy of this game.") }
        sessions.setGoals(Array(ids.prefix(6)))
        return Done(ok: true, detail: "Goals set: \(min(ids.count, 6))")
    }

    private func setStatus(_ input: JSONValue) throws -> Done {
        let game = try requireGame(input)
        guard let raw = input["status"]?.stringValue, let status = GamePlanStatus(rawValue: raw) else {
            throw ToolError("status must be one of chasing, later, skip, none")
        }
        try store.setPlan(status, for: game.id, at: now())
        return Done(ok: true, detail: "\(game.name): \(status.rawValue)")
    }

    private func saveNote(_ input: JSONValue) throws -> Done {
        let game = try requireGame(input)
        let trophyId = input["trophy_id"]?.numberValue.map(Int.init)
        if let trophyId, !game.trophies.contains(where: { $0.trophyId == trophyId }) {
            throw ToolError("No trophy \(trophyId) in this game.")
        }
        let text = input["text"]?.stringValue ?? ""
        try store.setNote(text, gameId: game.id, trophyId: trophyId, at: now())
        return Done(ok: true, detail: "Note saved")
    }

    private func saveSummary(_ input: JSONValue) throws -> Done {
        let id = input["session_id"]?.stringValue ?? ""
        let session = try store.session(id) ?? store.sessions(limit: 1).first
        guard let session else { throw ToolError("No such session.") }
        guard let summary = input["summary"]?.stringValue, !summary.isEmpty else { throw ToolError("summary is empty") }
        try store.setSummary(summary, nextSteps: input["next_steps"]?.stringValue, for: session)
        return Done(ok: true, detail: "Summary saved")
    }

    // MARK: Helpers

    // MARK: PlayStation's Game Help

    private struct GameHelpAnswer: Encodable {
        struct Trophy: Encodable {
            let id: Int
            let name: String?
            let hidden: Bool
            let earned: Bool
        }

        struct Help: Encodable {
            struct Step: Encodable {
                let title: String?
                let text: String?
                let has_video: Bool
            }

            let trophy_id: Int
            let name: String?
            let steps: [Step]
        }

        /// Without trophy_ids: the trophies that have help.
        let trophies_with_help: [Trophy]?
        /// With trophy_ids: their help.
        let help: [Help]?
        let note: String?
    }

    /// PlayStation's own help: which trophies of a game have it, or the help of up to five.
    private func getGameHelp(_ input: JSONValue) async throws -> GameHelpAnswer {
        guard let gameHelp else { throw ToolError("PlayStation's Game Help is not available in this app.") }
        let game = try requireGame(input)
        let trophies = Dictionary(game.trophies.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        let asked = (input["trophy_ids"]?.arrayValue ?? []).compactMap { $0.numberValue.map(Int.init) }
        // A hidden trophy not earned yet keeps its name: list_trophies' rule.
        func name(_ id: Int) -> String? {
            guard let trophy = trophies[id] else { return nil }
            return trophy.isHidden && !trophy.isEarned ? nil : trophy.name
        }
        guard !asked.isEmpty else {
            let ids = await gameHelp.helpedTrophyIds(gameId: game.id).sorted()
            return GameHelpAnswer(
                trophies_with_help: ids.map { id in
                    GameHelpAnswer.Trophy(
                        id: id, name: name(id), hidden: trophies[id]?.isHidden ?? false, earned: trophies[id]?.isEarned ?? false
                    )
                },
                help: nil,
                note: ids.isEmpty ? "No trophy of this game has PlayStation's Game Help, or PSN did not answer." : nil
            )
        }
        let ids = Array(asked.prefix(5))
        let found = await gameHelp.helps(gameId: game.id, trophyIds: ids)
        let help = ids.compactMap { id -> GameHelpAnswer.Help? in
            guard let item = found[id] else { return nil }
            return GameHelpAnswer.Help(
                trophy_id: id,
                name: name(id),
                steps: item.tips.map { GameHelpAnswer.Help.Step(title: $0.title, text: $0.text, has_video: $0.videoURL != nil) }
            )
        }
        let without = ids.filter { found[$0] == nil }
        return GameHelpAnswer(
            trophies_with_help: nil,
            help: help,
            note: without.isEmpty ? nil : "No Game Help for trophies \(without.map(String.init).joined(separator: ", "))."
        )
    }

    // MARK: Walkthrough

    private func walkthroughBrief(gameId: String) -> WalkthroughBrief? {
        guard let walkthroughs, let plan = walkthroughs.walkthrough(for: gameId) else { return nil }
        let current = walkthroughs.position(gameId: gameId)?.currentChapterId.flatMap { plan.chapter($0) }
        return WalkthroughBrief(chapters: plan.chapters.count, current_chapter: current.map { ChapterRef(id: $0.id, title: $0.title) })
    }

    private struct WalkthroughAnswer: Encodable {
        struct Missable: Encodable {
            let trophy_id: Int?
            /// nil for a hidden trophy not earned yet.
            let trophy_name: String?
            let earned: Bool?
            let note: String
        }

        struct Collectibles: Encodable {
            let kind: String
            let count: Int
        }

        struct Chapter: Encodable {
            let id: String
            let title: String
            let summary: String
            let state: String
            let missable: [Missable]
            let choices: [String]
            let collectibles: [Collectibles]
            let trophy_ids: [Int]
            let completion_trophy_id: Int?
            let playthrough: Int
        }

        let overview: String
        let playthroughs: Int?
        let current_chapter: ChapterRef?
        let chapters: [Chapter]
        let cleanup: String
        let sources: [Guide.Source]
    }

    private func requireWalkthroughs() throws -> WalkthroughService {
        guard let walkthroughs, walkthroughs.isAvailable else { throw ToolError("Walkthroughs are not available in this app.") }
        return walkthroughs
    }

    /// The game's walkthrough plan with where the person is; built first when there is none.
    private func getWalkthrough(_ input: JSONValue) async throws -> WalkthroughAnswer {
        let walkthroughs = try requireWalkthroughs()
        let game = try requireGame(input)
        guard let plan = await walkthroughs.walkthroughBuildingIfNeeded(gameId: game.id) else {
            throw ToolError("No walkthrough could be built for this game right now.")
        }
        let position = walkthroughs.position(gameId: game.id)
        let trophies = Dictionary(game.trophies.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        return WalkthroughAnswer(
            overview: plan.overview,
            playthroughs: plan.playthroughs,
            current_chapter: position?.currentChapterId.flatMap { plan.chapter($0) }.map { ChapterRef(id: $0.id, title: $0.title) },
            chapters: plan.chapters.map { chapter in
                WalkthroughAnswer.Chapter(
                    id: chapter.id,
                    title: chapter.title,
                    summary: chapter.summary,
                    state: (position?.state(of: chapter.id) ?? .ahead).rawValue,
                    missable: chapter.missable.map { item in
                        let trophy = item.trophyId.flatMap { trophies[$0] }
                        return WalkthroughAnswer.Missable(
                            trophy_id: item.trophyId,
                            trophy_name: trophy.flatMap { $0.isHidden && !$0.isEarned ? nil : $0.name },
                            earned: trophy?.isEarned,
                            note: item.note
                        )
                    },
                    choices: chapter.choices,
                    collectibles: chapter.collectibles.map { .init(kind: $0.kind, count: $0.count) },
                    trophy_ids: chapter.trophyIds,
                    completion_trophy_id: chapter.completionTrophyId,
                    playthrough: chapter.playthrough
                )
            },
            cleanup: plan.cleanup,
            sources: plan.sources
        )
    }

    private struct ChapterAnswer: Encodable {
        struct Header: Encodable {
            let id: String
            let title: String
            let state: String
        }

        struct Step: Encodable {
            let id: String
            let kind: String
            let text: String
            let done: Bool
            let spoiler: Bool
            let trophy_ids: [Int]
            let collectible: ChapterSteps.Step.Collectible?
            let has_image: Bool
            let has_video: Bool
            let source_id: String?
        }

        let chapter: Header
        let steps: [Step]
        let next_step_id: String?
        let sources: [Guide.Source]
    }

    /// A chapter's steps (the current chapter by default), with which are done.
    private func getChapter(_ input: JSONValue) async throws -> ChapterAnswer {
        let walkthroughs = try requireWalkthroughs()
        let game = try requireGame(input)
        guard let plan = await walkthroughs.walkthroughBuildingIfNeeded(gameId: game.id) else {
            throw ToolError("No walkthrough could be built for this game right now.")
        }
        let position = walkthroughs.position(gameId: game.id)
        let chapterId = input["chapter_id"]?.stringValue ?? position?.currentChapterId ?? plan.chapters.last?.id
        guard let chapterId, let chapter = plan.chapter(chapterId) else {
            throw ToolError("No chapter \(input["chapter_id"]?.stringValue ?? "") in this walkthrough; take an id from get_walkthrough.")
        }
        guard let steps = await walkthroughs.chapterBuildingIfNeeded(gameId: game.id, chapterId: chapter.id) else {
            throw ToolError("The steps of this chapter could not be built right now.")
        }
        let state = position?.state(of: chapter.id) ?? .ahead
        let earned = (try? store.earnedTrophyIds(gameId: game.id)) ?? []
        let marks = walkthroughs.marks(gameId: game.id)
        let lines = steps.steps.map { step in
            ChapterAnswer.Step(
                id: step.id,
                kind: step.kind.rawValue,
                text: step.text,
                done: WalkthroughPosition.isStepDone(step, chapterId: chapter.id, earned: earned, marks: marks, chapterState: state),
                spoiler: step.spoiler,
                trophy_ids: step.trophyIds,
                collectible: step.collectible,
                has_image: step.image != nil,
                has_video: step.video != nil,
                source_id: step.sourceId
            )
        }
        return ChapterAnswer(
            chapter: .init(id: chapter.id, title: chapter.title, state: state.rawValue),
            steps: lines,
            next_step_id: lines.first { !$0.done }?.id,
            sources: steps.sources
        )
    }

    private struct ProgressAnswer: Encodable {
        struct NextStep: Encodable {
            let chapter_id: String
            let id: String
            let text: String
            let spoiler: Bool
        }

        let saved: Bool
        let current_chapter: ChapterRef?
        let next_step: NextStep?
    }

    /// What the person said they did: steps, a chapter, or the chapter they are on.
    private func setWalkthroughProgress(_ input: JSONValue) throws -> ProgressAnswer {
        let walkthroughs = try requireWalkthroughs()
        let game = try requireGame(input)
        guard let plan = walkthroughs.walkthrough(for: game.id) else { throw ToolError("This game has no walkthrough yet: call get_walkthrough first.") }
        guard let chapterId = input["chapter_id"]?.stringValue, plan.chapter(chapterId) != nil else {
            throw ToolError("chapter_id must be a chapter of this walkthrough, from get_walkthrough.")
        }
        let known = Set(walkthroughs.chapter(gameId: game.id, chapterId: chapterId)?.steps.map(\.id) ?? [])
        let done = (input["done_step_ids"]?.arrayValue ?? []).compactMap(\.stringValue)
        let undone = (input["undone_step_ids"]?.arrayValue ?? []).compactMap(\.stringValue)
        let unknown = (done + undone).filter { !known.contains($0) }
        if !unknown.isEmpty {
            throw ToolError("No steps \(unknown.joined(separator: ", ")) in chapter \(chapterId); take ids from get_chapter.")
        }
        for step in done { walkthroughs.setStep(step, done: true, gameId: game.id, chapterId: chapterId) }
        for step in undone { walkthroughs.setStep(step, done: false, gameId: game.id, chapterId: chapterId) }
        if input["current"]?.boolValue == true { walkthroughs.setCurrentChapter(chapterId, gameId: game.id) }
        if let chapterDone = input["chapter_done"]?.boolValue { walkthroughs.setChapter(chapterId, done: chapterDone, gameId: game.id) }

        let position = walkthroughs.position(gameId: game.id)
        let current = position?.currentChapterId.flatMap { plan.chapter($0) }
        var next: ProgressAnswer.NextStep?
        if let current, let steps = walkthroughs.chapter(gameId: game.id, chapterId: current.id) {
            let earned = (try? store.earnedTrophyIds(gameId: game.id)) ?? []
            if let step = WalkthroughPosition.nextStep(
                in: steps, earned: earned, marks: walkthroughs.marks(gameId: game.id), chapterState: position?.state(of: current.id) ?? .current
            ) {
                next = ProgressAnswer.NextStep(chapter_id: current.id, id: step.id, text: step.text, spoiler: step.spoiler)
            }
        }
        return ProgressAnswer(saved: true, current_chapter: current.map { ChapterRef(id: $0.id, title: $0.title) }, next_step: next)
    }

    private struct ToolError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func requireGame(_ input: JSONValue) throws -> GameRecord {
        guard let id = input["game_id"]?.stringValue else { throw ToolError("game_id is required") }
        guard let game = try store.game(id) else { throw ToolError("No game \(id) in the library.") }
        return game
    }

    private func summaries() throws -> [GameSummary] {
        let plans = try store.plans()
        return try store.games().map { $0.summary(status: plans[$0.id] ?? .none) }
    }

    private func encode<T: Encodable>(_ value: T) throws -> AssistantToolOutput {
        .success(try JSONValue.encoding(value))
    }
}
#endif
