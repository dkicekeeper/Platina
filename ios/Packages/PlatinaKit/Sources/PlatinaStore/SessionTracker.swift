#if canImport(SwiftData)
import Foundation
import Observation
import PSNKit
import PlatinaCore

/// The running session (docs/PLAN.md §3.5): start, pause, goals, the check for new trophies,
/// the end. The app shows it, mirrors it into the Live Activity (`onChange`) and celebrates
/// (`onEarned`); this class keeps it in the store.
@MainActor
@Observable
public final class SessionTracker {
    public private(set) var current: PlaySessionRecord?
    /// Trophies the last check found, for the celebration.
    public private(set) var lastEarned: [TrophyRecord] = []
    public private(set) var isChecking = false
    public private(set) var lastCheckedAt: Date?

    /// The session changed (started, paused, goals, trophies, ended): the Live Activity follows.
    @ObservationIgnored public var onChange: ((PlaySessionRecord?) -> Void)?
    /// New trophies were found during the session.
    @ObservationIgnored public var onEarned: (([TrophyRecord], PlaySessionRecord) -> Void)?
    /// A session just ended: Plati writes its summary (stage 3).
    @ObservationIgnored public var onEnded: ((PlaySessionRecord) -> Void)?

    /// How often the screen checks for new trophies while the app is open.
    public let checkInterval: TimeInterval

    private let store: LibraryStore
    private let sync: LibrarySync
    private let now: () -> Date

    public init(store: LibraryStore, sync: LibrarySync, checkInterval: TimeInterval = 120, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.sync = sync
        self.checkInterval = checkInterval
        self.now = now
        current = try? store.runningSession()
    }

    public var isRunning: Bool { current != nil }

    /// Takes the store's running session as the current one: a session put in the store outside
    /// the tracker (the App Store screenshots' demo seeds one).
    public func adoptRunningSession() {
        current = try? store.runningSession()
        lastEarned = []
        onChange?(current)
    }

    /// Starts a session in a game (ending one in another game first).
    public func start(gameId: String) async {
        // Time played before the session: what PSN says now, so the end can tell the difference.
        await sync.refreshPlayTime()
        guard let session = try? store.startSession(gameId: gameId, at: now()) else { return }
        current = session
        lastEarned = []
        onChange?(session)
    }

    public func pause() {
        guard let current else { return }
        try? store.pause(current, at: now())
        onChange?(current)
    }

    public func resume() {
        guard let current else { return }
        try? store.resume(current, at: now())
        onChange?(current)
    }

    /// Looks for new trophies of the session's game. Quiet while one check runs.
    @discardableResult
    public func check() async -> [TrophyRecord] {
        guard let session = current, !isChecking else { return [] }
        isChecking = true
        defer {
            isChecking = false
            lastCheckedAt = now()
        }
        guard let earned = try? await sync.checkGame(session.gameId), !earned.isEmpty else { return [] }
        try? store.recordEarned(earned.map(\.trophyId), in: session)
        lastEarned = earned
        onEarned?(earned, session)
        onChange?(session)
        return earned
    }

    /// Whether a check is due: the app's timer asks it while the screen is on.
    public var isCheckDue: Bool {
        guard current != nil, !isChecking else { return false }
        guard let lastCheckedAt else { return true }
        return now().timeIntervalSince(lastCheckedAt) >= checkInterval
    }

    public func setGoals(_ trophyIds: [Int]) {
        guard let current else { return }
        try? store.setGoals(trophyIds, for: current)
        onChange?(current)
    }

    public func toggleGoal(_ trophyId: Int) {
        guard let current else { return }
        try? store.toggleGoal(trophyId, in: current)
        onChange?(current)
    }

    public func setNote(_ text: String) {
        guard let current else { return }
        try? store.setNote(text, for: current)
    }

    /// Ends the session: a last look for trophies and at the time played, then the journal.
    public func end() async {
        guard let session = current else { return }
        await check()
        await sync.refreshPlayTime()
        try? store.endSession(session, at: now())
        current = nil
        lastEarned = []
        onChange?(nil)
        onEnded?(session)
    }

    /// The goals of the running session as trophies, in the order they were set.
    public func goalTrophies() -> [TrophyRecord] {
        guard let current, let game = try? store.game(current.gameId) else { return [] }
        let byId = Dictionary(game.trophies.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        return current.goalTrophyIds.compactMap { byId[$0] }
    }
}
#endif
