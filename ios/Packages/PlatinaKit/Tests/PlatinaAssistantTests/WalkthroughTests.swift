import Foundation
import Testing
@testable import PlatinaAssistant

@Suite("Walkthrough")
struct WalkthroughTests {
    static let planJSON = """
    {"gameId":"NPWR12345_00","language":"ru","generatedAt":"2026-11-23T12:00:00Z","overview":"Один проход.",
    "playthroughs":2,"chapters":[
    {"id":"c1","title":"Пролог","summary":"Деревня.","missable":[{"trophyId":4,"note":"Пощади рыцаря."}],
    "choices":["Пощадить рыцаря"],"collectibles":[{"kind":"Реликвии","count":3}],"trophyIds":[1,4],
    "completionTrophyId":1,"playthrough":1,"sourceIds":["w1"]},
    {"id":"c2","title":"Замок","summary":"Штурм.","completionTrophyId":2,"playthrough":1},
    {"id":"c3","title":"Башня","summary":"Финал.","completionTrophyId":3,"playthrough":1},
    {"id":"c4","title":"Пролог (НИ+)","summary":"Второй проход.","completionTrophyId":1,"playthrough":2}],
    "cleanup":"Добери реликвии.","sources":[{"id":"w1","title":"PowerPyx","url":"https://www.powerpyx.com/x/"}]}
    """

    static let chapterJSON = """
    {"gameId":"NPWR12345_00","language":"ru","chapterId":"c1","walkthroughGeneratedAt":"2026-11-23T12:00:00Z",
    "generatedAt":"2026-11-23T12:05:00Z","steps":[
    {"id":"s1","kind":"path","text":"Иди налево.","trophyIds":[],"spoiler":false,"collectible":null,"sourceId":"w1","image":null,"video":null},
    {"id":"s2","kind":"collectible","text":"Реликвия 1.","trophyIds":[5],"spoiler":false,"collectible":{"kind":"Реликвия","number":1},
    "sourceId":"w1","image":{"url":"https://www.powerpyx.com/a.jpg","sourceId":"w1"},"video":{"youtubeId":"dQw4w9WgXcQ","startSeconds":95}},
    {"id":"s3","kind":"point_of_no_return","text":"Дальше не вернуться.","trophyIds":[]},
    {"id":"s4","kind":"dance","text":"Новый вид шага."}],
    "sources":[{"id":"w1","title":"PowerPyx","url":"https://www.powerpyx.com/x/"}]}
    """

    static func plan() throws -> Walkthrough {
        try JSONDecoder().decode(Walkthrough.self, from: Data(planJSON.utf8))
    }

    static func chapter() throws -> ChapterSteps {
        try JSONDecoder().decode(ChapterSteps.self, from: Data(chapterJSON.utf8))
    }

    @Test("A plan decodes, with missing lists as empty")
    func decodesPlan() throws {
        let plan = try Self.plan()
        #expect(plan.chapters.map(\.id) == ["c1", "c2", "c3", "c4"])
        #expect(plan.chapters[0].hasWarnings)
        #expect(!plan.chapters[1].hasWarnings)
        #expect(plan.chapters[1].missable.isEmpty)
        #expect(plan.sources(of: plan.chapters[0]).map(\.url) == ["https://www.powerpyx.com/x/"])
    }

    @Test("A chapter decodes; a kind it doesn't know reads as a tip")
    func decodesChapter() throws {
        let chapter = try Self.chapter()
        #expect(chapter.steps.map(\.kind) == [.path, .collectible, .pointOfNoReturn, .tip])
        #expect(chapter.steps[1].collectible == .init(kind: "Реликвия", number: 1))
        #expect(chapter.steps[1].video?.url?.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=95s")
        #expect(chapter.steps[2].kind.isWarning)
        #expect(chapter.source("w1")?.title == "PowerPyx")
    }

    @Test("Stream events: the plan, a chapter, an error")
    func events() throws {
        let plan = WalkthroughStreamEvent(.init(name: "walkthrough", data: Self.planJSON.replacingOccurrences(of: "\n", with: "")))
        #expect(plan == .walkthrough(try Self.plan()))
        let chapter = WalkthroughStreamEvent(.init(name: "chapter", data: Self.chapterJSON.replacingOccurrences(of: "\n", with: "")))
        #expect(chapter == .chapter(try Self.chapter()))
        #expect(WalkthroughStreamEvent(.init(name: "error", data: #"{"code":"no_walkthrough","retryable":false}"#)) == .error(code: "no_walkthrough", retryable: false))
        #expect(WalkthroughStreamEvent(.init(name: "progress", data: #"{"step":"reading"}"#)) == .progress(step: "reading"))
        #expect(WalkthroughStreamEvent(.init(name: "chapter", data: "{}")) == .error(code: "invalid", retryable: true))
    }

    @Test("A chapter request carries the chapter")
    func request() throws {
        let game = GuideRequest.Game(npCommunicationId: "NPWR12345_00", name: "Test", platform: "PS5", trophySetVersion: "01.00", trophies: [])
        let data = try JSONEncoder().encode(ChapterRequest(language: "ru", refresh: false, game: game, chapterId: "c2"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["chapterId"] as? String == "c2")
        #expect(object["protocol"] as? Int == AssistantProtocol.version)
    }

    @Test("Nothing done: the first chapter is now")
    func fresh() throws {
        let position = WalkthroughPosition(walkthrough: try Self.plan(), earned: [], marks: .init())
        #expect(position.currentChapterId == "c1")
        #expect(position.state(of: "c1") == .current)
        #expect(position.state(of: "c2") == .ahead)
    }

    @Test("A completion trophy puts every chapter before it behind")
    func byTrophy() throws {
        let position = WalkthroughPosition(walkthrough: try Self.plan(), earned: [2], marks: .init())
        #expect(position.state(of: "c1") == .done)
        #expect(position.state(of: "c2") == .done)
        #expect(position.currentChapterId == "c3")
    }

    @Test("A second playthrough's chapter isn't done by the first one's trophy")
    func secondPlaythrough() throws {
        let position = WalkthroughPosition(walkthrough: try Self.plan(), earned: [1], marks: .init())
        #expect(position.state(of: "c1") == .done)
        #expect(position.currentChapterId == "c2")
        #expect(position.state(of: "c4") == .ahead)
    }

    @Test("The player's own marks: done by hand, and the chapter they say they are on")
    func byHand() throws {
        let plan = try Self.plan()
        let done = WalkthroughPosition(walkthrough: plan, earned: [], marks: .init(doneChapters: ["c1", "c2"]))
        #expect(done.currentChapterId == "c3")
        let chosen = WalkthroughPosition(walkthrough: plan, earned: [3], marks: .init(currentChapter: "c2"))
        #expect(chosen.currentChapterId == "c2")
        #expect(chosen.state(of: "c1") == .done)
        #expect(chosen.state(of: "c3") == .ahead)
        let all = WalkthroughPosition(walkthrough: plan, earned: [], marks: .init(doneChapters: ["c1", "c2", "c3", "c4"]))
        #expect(all.currentChapterId == nil)
    }

    @Test("A step is done when ticked, when its trophies are earned, or when its chapter is behind")
    func steps() throws {
        let chapter = try Self.chapter()
        let marks = WalkthroughMarks(checkedSteps: [WalkthroughMarks.stepKey(chapterId: "c1", stepId: "s1")])
        #expect(WalkthroughPosition.isStepDone(chapter.steps[0], chapterId: "c1", earned: [], marks: marks, chapterState: .current))
        #expect(!WalkthroughPosition.isStepDone(chapter.steps[1], chapterId: "c1", earned: [], marks: marks, chapterState: .current))
        #expect(WalkthroughPosition.isStepDone(chapter.steps[1], chapterId: "c1", earned: [5], marks: marks, chapterState: .current))
        #expect(WalkthroughPosition.isStepDone(chapter.steps[2], chapterId: "c1", earned: [], marks: .init(), chapterState: .done))
        #expect(WalkthroughPosition.nextStep(in: chapter, earned: [5], marks: marks, chapterState: .current)?.id == "s3")
    }
}
