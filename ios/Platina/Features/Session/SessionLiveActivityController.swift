import ActivityKit
import Foundation
import PlatinaShared
import PlatinaStore

/// Starts, updates and ends the session's Live Activity (docs/domains/screens.md §3.5). The clock on the
/// lock screen runs by itself; the app pushes a new state when the session changes: a pause, a
/// goal, a trophy.
@MainActor
final class SessionLiveActivityController {
    private var activityId: String?
    private var lastState: SessionActivityAttributes.ContentState?

    func update(
        session: PlaySessionRecord?, game: GameRecord?, goals: [TrophyRecord], lastTrophy: TrophyRecord?,
        step: SessionActivityAttributes.ContentState.Step? = nil
    ) {
        guard let session, session.isRunning else {
            end()
            return
        }
        var state = Self.state(session: session, game: game, goals: goals, lastTrophy: lastTrophy)
        state.step = step
        // After a relaunch the activity may still be on screen: carry on with it.
        let existing = Activity<SessionActivityAttributes>.activities.first { $0.attributes.gameId == session.gameId }
        if activityId == nil, let existing {
            activityId = existing.id
        }
        if activityId == nil {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            // Another game's activity from a session that ended while the app was away.
            endAll(except: nil)
            let attributes = SessionActivityAttributes(gameId: session.gameId, gameName: session.gameName)
            let activity = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            activityId = activity?.id
            lastState = state
            return
        }
        guard state != lastState else { return }
        push(state)
    }

    func end() {
        activityId = nil
        lastState = nil
        endAll(except: nil)
    }

    private func endAll(except keptId: String?) {
        // `Activity` is not Sendable: look it up again inside the task.
        Task.detached {
            for activity in Activity<SessionActivityAttributes>.activities where activity.id != keptId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func push(_ state: SessionActivityAttributes.ContentState) {
        guard let id = activityId else { return }
        lastState = state
        Task.detached {
            guard let activity = Activity<SessionActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private static func state(
        session: PlaySessionRecord, game: GameRecord?, goals: [TrophyRecord], lastTrophy: TrophyRecord?
    ) -> SessionActivityAttributes.ContentState {
        let done = goals.filter { session.isGoalDone($0.trophyId) }.count
        let next = goals.first { !session.isGoalDone($0.trophyId) }
        let status: String?
        if session.isPaused {
            status = String(localized: "session.paused")
        } else if let lastTrophy {
            status = String(localized: "session.activity.newTrophy \(lastTrophy.name)")
        } else {
            status = nil
        }
        return SessionActivityAttributes.ContentState(
            clockStart: session.clockStart,
            pausedElapsed: session.isPaused ? session.elapsed(at: Date()) : nil,
            progress: game?.progress ?? session.startProgress,
            trophiesText: String(localized: "session.activity.trophies \(session.earnedTrophyIds.count)"),
            goalsText: goals.isEmpty ? nil : String(localized: "session.activity.goals \(done) \(goals.count)"),
            nextGoal: next?.name,
            statusText: status
        )
    }
}
