#if canImport(SwiftData)
import Foundation
import Observation
import SwiftData
import PlatinaAssistant

/// The walkthrough "by the hand" (docs/assistant.md §8, docs/PLAN.md §5): a game's chapters,
/// then each chapter's steps, each the stored copy first, then the server's cache (free), then a
/// build (a minute or two, and money: it runs when the person or Plati asks for it). Where the
/// player is comes from their trophies and their own marks (`WalkthroughProgressRecord`).
@MainActor
@Observable
public final class WalkthroughService {
    public enum BuildState: Equatable {
        case idle
        /// `start`, `search`, `reading`, `writing`.
        case building(step: String)
        case failed(String)
    }

    /// Build states by game (`NPWR…`) and by chapter (`NPWR…/c3`).
    public private(set) var states: [String: BuildState] = [:]
    /// Bumped on every stored plan, chapter or mark, so views redraw.
    public private(set) var revision = 0

    private let store: LibraryStore
    private let transport: (any WalkthroughTransport)?
    private let language: String
    private let now: () -> Date
    /// Called after a plan, a chapter or a mark changes: the Live Activity's step follows.
    @ObservationIgnored public var onChange: (() -> Void)?
    @ObservationIgnored private var plans: [String: Walkthrough] = [:]
    @ObservationIgnored private var chapters: [String: ChapterSteps] = [:]

    public init(store: LibraryStore, transport: (any WalkthroughTransport)?, language: String, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.transport = transport
        self.language = language
        self.now = now
    }

    public var isAvailable: Bool { transport != nil }

    public func state(for gameId: String) -> BuildState { states[gameId] ?? .idle }
    public func state(for gameId: String, chapterId: String) -> BuildState { states["\(gameId)/\(chapterId)"] ?? .idle }

    // MARK: Reading

    /// The stored plan of a game, if any.
    public func walkthrough(for gameId: String) -> Walkthrough? {
        _ = revision
        if let plan = plans[gameId] { return plan }
        let key = "\(gameId):\(language)"
        var descriptor = FetchDescriptor<WalkthroughRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let record = try? store.context.fetch(descriptor).first,
              let plan = try? JSONDecoder().decode(Walkthrough.self, from: record.json) else { return nil }
        plans[gameId] = plan
        return plan
    }

    /// A chapter's stored steps, if built against the stored plan.
    public func chapter(gameId: String, chapterId: String) -> ChapterSteps? {
        _ = revision
        guard let plan = walkthrough(for: gameId) else { return nil }
        let memoryKey = "\(gameId)/\(chapterId)"
        if let steps = chapters[memoryKey], steps.walkthroughGeneratedAt == plan.generatedAt { return steps }
        let key = "\(gameId):\(language):\(chapterId)"
        var descriptor = FetchDescriptor<ChapterRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let record = try? store.context.fetch(descriptor).first,
              let steps = try? JSONDecoder().decode(ChapterSteps.self, from: record.json),
              steps.walkthroughGeneratedAt == plan.generatedAt else { return nil }
        chapters[memoryKey] = steps
        return steps
    }

    /// The person's marks in a game's walkthrough.
    public func marks(gameId: String) -> WalkthroughMarks {
        _ = revision
        return (try? store.walkthroughMarks(gameId: gameId)) ?? WalkthroughMarks()
    }

    /// Where the player is: from the plan, their earned trophies and their marks.
    public func position(gameId: String) -> WalkthroughPosition? {
        guard let plan = walkthrough(for: gameId) else { return nil }
        let earned = (try? store.earnedTrophyIds(gameId: gameId)) ?? []
        return WalkthroughPosition(walkthrough: plan, earned: earned, marks: marks(gameId: gameId))
    }

    /// Whether a step counts as done now.
    public func isStepDone(_ step: ChapterSteps.Step, gameId: String, chapterId: String) -> Bool {
        let earned = (try? store.earnedTrophyIds(gameId: gameId)) ?? []
        let state = position(gameId: gameId)?.state(of: chapterId) ?? .ahead
        return WalkthroughPosition.isStepDone(step, chapterId: chapterId, earned: earned, marks: marks(gameId: gameId), chapterState: state)
    }

    /// The step to do now in a game: its current chapter's first step not done, if the steps are
    /// built.
    public func currentStep(gameId: String) -> (chapter: Walkthrough.Chapter, step: ChapterSteps.Step)? {
        guard let plan = walkthrough(for: gameId),
              let chapterId = position(gameId: gameId)?.currentChapterId,
              let chapter = plan.chapter(chapterId),
              let steps = self.chapter(gameId: gameId, chapterId: chapterId),
              let step = steps.steps.first(where: { !isStepDone($0, gameId: gameId, chapterId: chapterId) }) else { return nil }
        return (chapter, step)
    }

    // MARK: Fetching and building

    /// The server's cached plan, if someone already built it: free, so a game's screen asks.
    public func fetchCached(gameId: String) async {
        guard walkthrough(for: gameId) == nil, let transport else { return }
        if let plan = try? await transport.cachedWalkthrough(gameId: gameId, language: language) {
            save(plan)
        }
    }

    /// The server's cached steps of a chapter, if someone already built them.
    public func fetchCachedChapter(gameId: String, chapterId: String) async {
        guard chapter(gameId: gameId, chapterId: chapterId) == nil, walkthrough(for: gameId) != nil, let transport else { return }
        if let steps = try? await transport.cachedChapter(gameId: gameId, language: language, chapterId: chapterId) {
            save(steps)
        }
    }

    /// Builds (or rebuilds) a game's plan on the server and stores it.
    @discardableResult
    public func build(gameId: String, refresh: Bool = false) async -> Walkthrough? {
        guard let transport, let game = guideGame(gameId) else { return nil }
        if case .building = state(for: gameId) { return nil }
        states[gameId] = .building(step: "start")
        let request = GuideRequest(language: language, refresh: refresh, game: game)
        let outcome = await run(transport.walkthrough(request), key: gameId)
        if case .walkthrough(let plan)? = outcome {
            save(plan)
            return plan
        }
        return nil
    }

    /// Builds (or rebuilds) a chapter's steps; the plan first if there is none.
    @discardableResult
    public func buildChapter(gameId: String, chapterId: String, refresh: Bool = false) async -> ChapterSteps? {
        guard let transport, let game = guideGame(gameId) else { return nil }
        let key = "\(gameId)/\(chapterId)"
        if case .building = state(for: gameId, chapterId: chapterId) { return nil }
        if walkthrough(for: gameId) == nil, await walkthroughBuildingIfNeeded(gameId: gameId) == nil { return nil }
        states[key] = .building(step: "start")
        let request = ChapterRequest(language: language, refresh: refresh, game: game, chapterId: chapterId)
        var outcome = await run(transport.chapter(request), key: key)
        if case .error("no_walkthrough", _)? = outcome {
            // The server's plan expired before ours: build it there again, then the chapter.
            states[key] = .building(step: "start")
            guard await build(gameId: gameId, refresh: true) != nil else {
                states[key] = .failed("no_walkthrough")
                return nil
            }
            outcome = await run(transport.chapter(request), key: key)
        }
        if case .chapter(let steps)? = outcome {
            if refresh { clearChecks(gameId: gameId, chapterId: chapterId) }
            save(steps)
            return steps
        }
        return nil
    }

    /// The plan, from the store, the server's cache, or built: what Plati's `get_walkthrough` asks.
    public func walkthroughBuildingIfNeeded(gameId: String) async -> Walkthrough? {
        if let plan = walkthrough(for: gameId) { return plan }
        await fetchCached(gameId: gameId)
        if let plan = walkthrough(for: gameId) { return plan }
        return await build(gameId: gameId)
    }

    /// A chapter's steps, from the store, the server's cache, or built: Plati's `get_chapter`.
    public func chapterBuildingIfNeeded(gameId: String, chapterId: String) async -> ChapterSteps? {
        if let steps = chapter(gameId: gameId, chapterId: chapterId) { return steps }
        guard await walkthroughBuildingIfNeeded(gameId: gameId) != nil else { return nil }
        await fetchCachedChapter(gameId: gameId, chapterId: chapterId)
        if let steps = chapter(gameId: gameId, chapterId: chapterId) { return steps }
        return await buildChapter(gameId: gameId, chapterId: chapterId)
    }

    // MARK: Marks

    public func setStep(_ stepId: String, done: Bool, gameId: String, chapterId: String) {
        mark(gameId: gameId) { marks in
            let key = WalkthroughMarks.stepKey(chapterId: chapterId, stepId: stepId)
            if done { marks.checkedSteps.insert(key) } else { marks.checkedSteps.remove(key) }
        }
    }

    public func setChapter(_ chapterId: String, done: Bool, gameId: String) {
        mark(gameId: gameId) { marks in
            if done {
                marks.doneChapters.insert(chapterId)
                if marks.currentChapter == chapterId { marks.currentChapter = nil }
            } else {
                marks.doneChapters.remove(chapterId)
            }
        }
    }

    /// The chapter the player says they are on; nil: worked out from trophies and marks.
    public func setCurrentChapter(_ chapterId: String?, gameId: String) {
        mark(gameId: gameId) { marks in
            marks.currentChapter = chapterId
            if let chapterId { marks.doneChapters.remove(chapterId) }
        }
    }

    // MARK: Private

    private func mark(gameId: String, _ change: (inout WalkthroughMarks) -> Void) {
        try? store.updateWalkthroughMarks(gameId: gameId, at: now(), change)
        revision += 1
        onChange?()
    }

    /// A rebuilt chapter's steps are new: the old ticks would land on the wrong ones.
    private func clearChecks(gameId: String, chapterId: String) {
        mark(gameId: gameId) { marks in
            marks.checkedSteps = marks.checkedSteps.filter { !$0.hasPrefix("\(chapterId)/") }
        }
    }

    private func guideGame(_ gameId: String) -> GuideRequest.Game? {
        guard let game = try? store.game(gameId) else { return nil }
        return GuideRequest.Game(record: game)
    }

    /// Runs a build's stream, keeping its state; returns how it ended.
    private func run(_ stream: AsyncThrowingStream<WalkthroughStreamEvent, Error>, key: String) async -> WalkthroughStreamEvent? {
        do {
            for try await event in stream {
                switch event {
                case .progress(let step):
                    states[key] = .building(step: step)
                case .walkthrough, .chapter:
                    states[key] = .idle
                    return event
                case .error(let code, _):
                    states[key] = .failed(code)
                    return event
                }
            }
            states[key] = .failed("no_result")
        } catch {
            states[key] = .failed(String(describing: error))
        }
        return nil
    }

    private func save(_ plan: Walkthrough) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        let key = "\(plan.gameId):\(language)"
        var descriptor = FetchDescriptor<WalkthroughRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let record = try? store.context.fetch(descriptor).first {
            record.json = data
            record.fetchedAt = now()
        } else {
            store.context.insert(WalkthroughRecord(gameId: plan.gameId, language: language, json: data, fetchedAt: now()))
        }
        try? store.context.save()
        plans[plan.gameId] = plan
        // A new plan: the chapters kept in memory may belong to the old one.
        chapters = chapters.filter { !$0.key.hasPrefix("\(plan.gameId)/") }
        revision += 1
        onChange?()
    }

    private func save(_ steps: ChapterSteps) {
        guard let data = try? JSONEncoder().encode(steps) else { return }
        let key = "\(steps.gameId):\(language):\(steps.chapterId)"
        var descriptor = FetchDescriptor<ChapterRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let record = try? store.context.fetch(descriptor).first {
            record.json = data
            record.fetchedAt = now()
        } else {
            store.context.insert(ChapterRecord(gameId: steps.gameId, language: language, chapterId: steps.chapterId, json: data, fetchedAt: now()))
        }
        try? store.context.save()
        chapters["\(steps.gameId)/\(steps.chapterId)"] = steps
        revision += 1
        onChange?()
    }
}

extension GuideRequest.Game {
    /// A stored game with its trophies, as the server's builds take it.
    init(record game: GameRecord) {
        self.init(
            npCommunicationId: game.id,
            name: game.name,
            platform: game.platform,
            trophySetVersion: game.trophySetVersion,
            trophies: game.trophies.sorted { $0.trophyId < $1.trophyId }.map {
                GuideRequest.Game.Trophy(
                    id: $0.trophyId, name: $0.name, detail: $0.detail, type: $0.typeRaw,
                    hidden: $0.isHidden, groupId: $0.groupId
                )
            }
        )
    }
}
#endif
