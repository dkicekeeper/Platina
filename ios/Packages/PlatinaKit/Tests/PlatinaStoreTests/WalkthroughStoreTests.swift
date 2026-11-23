#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing
import PSNKit
import PlatinaCore
import PlatinaAssistant
@testable import PlatinaStore

/// The server's walkthrough endpoints as a script.
final class ScriptedWalkthroughs: WalkthroughTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var plansBuilt = 0
    private var chaptersBuilt: [String] = []
    /// Answers the first chapter build with `no_walkthrough`, as a server whose plan expired.
    var forgetPlanOnce = false
    var cachedPlan: Walkthrough?

    var builds: (plans: Int, chapters: [String]) { lock.withLock { (plansBuilt, chaptersBuilt) } }

    static func plan(generatedAt: String = "2026-11-23T12:00:00Z") -> Walkthrough {
        Walkthrough(
            gameId: "NPWR28536_00", language: "ru", generatedAt: generatedAt, overview: "Один проход.", playthroughs: 1,
            chapters: [
                .init(id: "c1", title: "Начало", summary: "Культ.", missable: [.init(trophyId: 12, note: "Кости до финала.")], completionTrophyId: 40),
                .init(id: "c2", title: "Лес", summary: "Первый епископ.", trophyIds: [12]),
                .init(id: "c3", title: "Финал", summary: "Последний бой."),
            ],
            cleanup: "Добери кости.",
            sources: [.init(id: "w1", title: "PowerPyx", url: "https://www.powerpyx.com/x/")]
        )
    }

    func walkthrough(_ request: GuideRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error> {
        lock.withLock { plansBuilt += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(step: "search"))
            continuation.yield(.walkthrough(Self.plan()))
            continuation.finish()
        }
    }

    func chapter(_ request: ChapterRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error> {
        let forget = lock.withLock { () -> Bool in
            if forgetPlanOnce {
                forgetPlanOnce = false
                return true
            }
            chaptersBuilt.append(request.chapterId)
            return false
        }
        let steps = ChapterSteps(
            gameId: request.game.npCommunicationId, language: request.language, chapterId: request.chapterId,
            walkthroughGeneratedAt: Self.plan().generatedAt, generatedAt: "2026-11-23T12:05:00Z",
            steps: [
                .init(id: "s1", kind: .path, text: "Иди налево."),
                .init(id: "s2", kind: .choice, text: "Сыграй в кости.", trophyIds: [12]),
                .init(id: "s3", kind: .trophy, text: "Шерстополь.", trophyIds: [40], spoiler: true),
            ],
            sources: []
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(step: "reading"))
            continuation.yield(forget ? .error(code: "no_walkthrough", retryable: false) : .chapter(steps))
            continuation.finish()
        }
    }

    func cachedWalkthrough(gameId: String, language: String) async throws -> Walkthrough? { cachedPlan }
    func cachedChapter(gameId: String, language: String, chapterId: String) async throws -> ChapterSteps? { nil }
}

@MainActor
private func makeService(_ server: ScriptedWalkthroughs) async throws -> (WalkthroughService, LibraryStore) {
    let store = LibraryStore(container: try LibraryStore.makeContainer(inMemory: true))
    let tokens = PSNTokens(accessToken: "a1", accessTokenExpiresAt: Date().addingTimeInterval(3600), refreshToken: "r1", refreshTokenExpiresAt: Date().addingTimeInterval(86_400))
    let client = PSNClient(store: InMemoryTokenStore(tokens), transport: FakePSN(), language: "ru-RU")
    let sync = LibrarySync(client: client, store: store)
    await sync.sync()
    return (WalkthroughService(store: store, transport: server, language: "ru"), store)
}

@MainActor
@Suite("Walkthrough on the phone")
struct WalkthroughStoreTests {
    let gameId = "NPWR28536_00"

    @Test("The plan is fetched from the server's cache when there is one, built otherwise, and kept")
    func plan() async throws {
        let server = ScriptedWalkthroughs()
        server.cachedPlan = ScriptedWalkthroughs.plan(generatedAt: "2026-11-20T00:00:00Z")
        let (service, _) = try await makeService(server)
        let cached = await service.walkthroughBuildingIfNeeded(gameId: gameId)
        #expect(cached?.generatedAt == "2026-11-20T00:00:00Z")
        #expect(server.builds.plans == 0)

        let rebuilt = await service.build(gameId: gameId, refresh: true)
        #expect(rebuilt?.generatedAt == "2026-11-23T12:00:00Z")
        #expect(service.walkthrough(for: gameId)?.chapters.count == 3)
        #expect(service.state(for: gameId) == .idle)
    }

    @Test("Where the player is: the earned completion trophy puts the first chapter behind")
    func position() async throws {
        let (service, _) = try await makeService(ScriptedWalkthroughs())
        _ = await service.build(gameId: gameId)
        // Trophy 40 is earned in the fixtures: chapter 1 is done, chapter 2 is now.
        #expect(service.position(gameId: gameId)?.currentChapterId == "c2")
        service.setChapter("c2", done: true, gameId: gameId)
        #expect(service.position(gameId: gameId)?.currentChapterId == "c3")
        service.setCurrentChapter("c1", gameId: gameId)
        #expect(service.position(gameId: gameId)?.currentChapterId == "c1")
        #expect(service.position(gameId: gameId)?.state(of: "c3") == .ahead)
        service.setCurrentChapter(nil, gameId: gameId)
        #expect(service.position(gameId: gameId)?.currentChapterId == "c3")
    }

    @Test("A chapter is built after the plan; ticks are kept, and cleared when it is rebuilt")
    func chapter() async throws {
        let server = ScriptedWalkthroughs()
        let (service, store) = try await makeService(server)
        let steps = await service.chapterBuildingIfNeeded(gameId: gameId, chapterId: "c2")
        #expect(steps?.steps.count == 3)
        #expect(server.builds.plans == 1)
        #expect(server.builds.chapters == ["c2"])
        #expect(service.chapter(gameId: gameId, chapterId: "c2")?.steps.first?.text == "Иди налево.")

        let step = try #require(steps?.steps.first)
        #expect(!service.isStepDone(step, gameId: gameId, chapterId: "c2"))
        service.setStep("s1", done: true, gameId: gameId, chapterId: "c2")
        #expect(service.isStepDone(step, gameId: gameId, chapterId: "c2"))
        // Its trophy is earned: done without a tick.
        #expect(service.isStepDone(try #require(steps?.steps.last), gameId: gameId, chapterId: "c2"))
        #expect(try store.walkthroughMarks(gameId: gameId).checkedSteps == ["c2/s1"])

        _ = await service.buildChapter(gameId: gameId, chapterId: "c2", refresh: true)
        #expect(try store.walkthroughMarks(gameId: gameId).checkedSteps.isEmpty)
    }

    @Test("A plan the server lost is built again before the chapter")
    func lostPlan() async throws {
        let server = ScriptedWalkthroughs()
        let (service, _) = try await makeService(server)
        _ = await service.build(gameId: gameId)
        server.forgetPlanOnce = true
        let steps = await service.buildChapter(gameId: gameId, chapterId: "c1")
        #expect(steps != nil)
        #expect(server.builds.plans == 2)
        #expect(server.builds.chapters == ["c1"])
    }

    @Test("Marks from two devices are read together and become one record")
    func duplicates() async throws {
        let (_, store) = try await makeService(ScriptedWalkthroughs())
        let first = WalkthroughProgressRecord(gameId: gameId, updatedAt: Date(timeIntervalSince1970: 1))
        first.checkedSteps = ["c1/s1"]
        let second = WalkthroughProgressRecord(gameId: gameId, updatedAt: Date(timeIntervalSince1970: 2))
        second.doneChapters = ["c1"]
        second.currentChapter = "c2"
        store.context.insert(first)
        store.context.insert(second)
        try store.context.save()

        let marks = try store.walkthroughMarks(gameId: gameId)
        #expect(marks == WalkthroughMarks(checkedSteps: ["c1/s1"], doneChapters: ["c1"], currentChapter: "c2"))
        try store.updateWalkthroughMarks(gameId: gameId) { $0.checkedSteps.insert("c2/s1") }
        let records = try store.context.fetch(FetchDescriptor<WalkthroughProgressRecord>())
        #expect(records.count == 1)
        #expect(records.first?.checkedSteps == ["c1/s1", "c2/s1"])
    }
}
#endif
