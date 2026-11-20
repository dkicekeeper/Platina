#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The Live Activity of a play session: the lock screen and the Dynamic Island
/// (docs/PLAN.md §3.5). The app prepares every text in its own language, so the extension needs
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

        public init(
            clockStart: Date, pausedElapsed: TimeInterval?, progress: Int, trophiesText: String,
            goalsText: String?, nextGoal: String?, statusText: String?
        ) {
            self.clockStart = clockStart
            self.pausedElapsed = pausedElapsed
            self.progress = progress
            self.trophiesText = trophiesText
            self.goalsText = goalsText
            self.nextGoal = nextGoal
            self.statusText = statusText
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
