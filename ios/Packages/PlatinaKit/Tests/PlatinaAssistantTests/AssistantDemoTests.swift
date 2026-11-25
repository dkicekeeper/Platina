import Foundation
import Testing
@testable import PlatinaAssistant

/// Shows every display tool as shown, as the app's toolkit does.
@MainActor
private final class ShowingToolkit: AssistantToolExecuting {
    var calls: [(String, JSONValue)] = []

    func execute(name: String, input: JSONValue) async -> AssistantToolOutput {
        calls.append((name, input))
        return .success(["shown": true])
    }
}

/// The screenshots' Plati (`AssistantDemoTransport`) answers through the real conversation loop.
@Suite("Demo assistant")
@MainActor
struct AssistantDemoTests {
    @Test("The question gets a warning, the chapter's next steps, quick replies, then text", arguments: ["ru", "en"])
    func scriptedTurn(language: String) async throws {
        let toolkit = ShowingToolkit()
        let conversation = AssistantConversation(transport: AssistantDemoTransport(), toolkit: toolkit, language: language)
        let reply = try await conversation.send(AssistantDemoTransport.question(language: language))
        #expect(reply.tools == ["show_warning", "show_checklist", "suggest_replies"])
        #expect(reply.text.contains("33"))

        let chapter = try #require(AssistantDemoTransport.chapter(
            gameId: AssistantDemoTransport.gameId, language: language, chapterId: AssistantDemoTransport.currentChapterId
        ))
        let shown = try #require(toolkit.calls.first { $0.0 == "show_checklist" }?.1["step_ids"]?.arrayValue)
        let stepIds = Set(chapter.steps.map(\.id))
        #expect(shown.allSatisfy { stepIds.contains($0.stringValue ?? "") })
        #expect(Set(AssistantDemoTransport.checkedStepIds).isSubset(of: stepIds))
    }

    @Test("The guide, the plan and the current chapter are there for Emberfall only", arguments: ["ru", "en"])
    func content(language: String) async throws {
        let transport = AssistantDemoTransport()
        let id = AssistantDemoTransport.gameId
        let guide = try #require(try await transport.cachedGuide(gameId: id, language: language))
        #expect(guide.missable.map(\.trophyId) == [9, 10, 14])
        let plan = try #require(try await transport.cachedWalkthrough(gameId: id, language: language))
        #expect(plan.chapters.count == 8)
        #expect(plan.chapter(AssistantDemoTransport.currentChapterId)?.hasWarnings == true)
        // Every trophy named is one of Emberfall's 23 (PSNDemo).
        let ids = guide.steps.flatMap(\.trophyIds) + guide.missable.map(\.trophyId) + plan.chapters.flatMap(\.trophyIds)
        #expect(ids.allSatisfy { (0...22).contains($0) })
        #expect(try await transport.cachedChapter(gameId: id, language: language, chapterId: "c6")?.steps.count == 8)
        #expect(try await transport.cachedChapter(gameId: id, language: language, chapterId: "c2") == nil)
        #expect(try await transport.cachedGuide(gameId: "NPWR00000_00", language: language) == nil)

        // As the server's JSON, so the phone's cache keeps it.
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(Walkthrough.self, from: data) == plan)
    }
}
