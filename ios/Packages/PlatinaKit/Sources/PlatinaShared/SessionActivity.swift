#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The Live Activity of a play session: the lock screen and the Dynamic Island
/// (docs/domains/screens.md §3.5). The app prepares every text in its own language, so the extension needs
/// no strings of its own; the clock runs by itself (`Text(timerInterval:)`).
public struct SessionActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// When a clock that skips the pauses would have started.
        public var clockStart: Date
        /// While paused: the time played so far, frozen; nil while the clock runs.
        public var pausedElapsed: TimeInterval?
        /// The game's progress, 0–100.
        public var progress: Int
        /// "Trophies: 2", "Goals: 1 of 3".
        public var trophiesText: String
        public var goalsText: String?
        /// The next goal not reached yet.
        public var nextGoal: String?
        /// "Paused", or the last trophy earned: "New trophy: …".
        public var statusText: String?
        /// The walkthrough's step to do now, ticked with the activity's ✓ (docs/archive/plans/2026-11-20-stages.md, stage 8).
        public var step: Step?

        public struct Step: Codable, Hashable, Sendable {
            public var chapterId: String
            public var stepId: String
            /// The chapter's title, "Chapter 3 · The forest".
            public var chapterText: String
            /// The step, plain text (a spoiler step says so instead).
            public var text: String
            /// The ✓'s VoiceOver name.
            public var doneLabel: String

            public init(chapterId: String, stepId: String, chapterText: String, text: String, doneLabel: String) {
                self.chapterId = chapterId
                self.stepId = stepId
                self.chapterText = chapterText
                self.text = text
                self.doneLabel = doneLabel
            }
        }

        public init(
            clockStart: Date, pausedElapsed: TimeInterval?, progress: Int, trophiesText: String,
            goalsText: String?, nextGoal: String?, statusText: String?, step: Step? = nil
        ) {
            self.clockStart = clockStart
            self.pausedElapsed = pausedElapsed
            self.progress = progress
            self.trophiesText = trophiesText
            self.goalsText = goalsText
            self.nextGoal = nextGoal
            self.statusText = statusText
            self.step = step
        }
    }

    public var gameId: String
    public var gameName: String

    public init(gameId: String, gameName: String) {
        self.gameId = gameId
        self.gameName = gameName
    }
}
#endif
