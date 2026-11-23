import AppIntents
import Foundation

// Plati without hands (docs/PLAN.md, stage 8): "What's next in Platina" and "Done in Platina"
// through Siri, the Shortcuts app and the Action button. Siri says the walkthrough's step to do
// now: in the running session's game, or else in the game played last that has a walkthrough.

/// What the voice intents ask the app. The app sets it at launch (AppModel).
@MainActor
enum PlatiVoice {
    /// The step to do now, as a line to say; nil when no game has one.
    static var current: (() -> String?)?
    /// Ticks the step to do now and says the next one.
    static var completeCurrent: (() -> String?)?
}

/// "What's next?": Siri says the walkthrough's step to do now.
struct NextStepIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.nextStep.title"
    static let description = IntentDescription("intent.nextStep.description")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = PlatiVoice.current?() ?? String(localized: "intent.step.none")
        return .result(dialog: "\(line)")
    }
}

/// "Done": ticks the step to do now and says the next one.
struct CompleteCurrentStepIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.completeCurrent.title"
    static let description = IntentDescription("intent.completeCurrent.description")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = PlatiVoice.completeCurrent?() ?? String(localized: "intent.step.none")
        return .result(dialog: "\(line)")
    }
}

struct PlatinaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextStepIntent(),
            phrases: [
                "Что дальше в \(.applicationName)",
                "Следующий шаг в \(.applicationName)",
            ],
            shortTitle: "intent.nextStep.short",
            systemImageName: "arrow.forward.circle"
        )
        AppShortcut(
            intent: CompleteCurrentStepIntent(),
            phrases: [
                "Готово в \(.applicationName)",
                "Шаг сделан в \(.applicationName)",
            ],
            shortTitle: "intent.completeCurrent.short",
            systemImageName: "checkmark.circle"
        )
    }
}
