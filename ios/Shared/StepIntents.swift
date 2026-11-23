import AppIntents
import Foundation

// In both the app and the widget extension (project.yml): the Live Activity's ✓ is a button
// with this intent, and a Live Activity intent runs in the app, where the walkthrough is.

/// What the app does when a step is ticked outside it (the Live Activity's ✓). The app sets it
/// at launch; in the extension it stays nil, and the intent runs in the app anyway.
@MainActor
enum StepIntentHandler {
    static var complete: ((_ gameId: String, _ chapterId: String, _ stepId: String) -> Void)?
}

/// Ticks a walkthrough step from the Live Activity, without opening the app.
struct CompleteStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "intent.completeStep.title"
    static let isDiscoverable = false

    @Parameter(title: "intent.param.game")
    var gameId: String

    @Parameter(title: "intent.param.chapter")
    var chapterId: String

    @Parameter(title: "intent.param.step")
    var stepId: String

    init() {}

    init(gameId: String, chapterId: String, stepId: String) {
        self.gameId = gameId
        self.chapterId = chapterId
        self.stepId = stepId
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        StepIntentHandler.complete?(gameId, chapterId, stepId)
        return .result()
    }
}
