import Foundation
import Observation
import SwiftData
import PSNKit
import PlatinaStore

/// The app's session: signed in to PSN or not, the client, the store and the sync.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    /// Why the person was signed out, shown once on the sign-in screen.
    var signOutReason: String?

    let client: PSNClient
    let store: LibraryStore
    let sync: LibrarySync
    let sessions: SessionTracker

    /// The session screen is open.
    var isShowingSession = false
    /// A session that just ended, for its summary sheet.
    var endedSession: PlaySessionRecord?
    /// Trophies earned during the session that the screen has not celebrated yet.
    private(set) var celebration: Celebration?

    struct Celebration: Equatable {
        let id = UUID()
        let trophyNames: [String]
        let isPlatinum: Bool
    }

    private let liveActivity = SessionLiveActivityController()

    init(container: ModelContainer, client: PSNClient? = nil) {
        let client = client ?? PSNClient(
            store: KeychainTokenStore(service: "dakacom.Platina.psn"),
            transport: URLSessionTransport(),
            language: AppLanguage.psnLanguage
        )
        self.client = client
        store = LibraryStore(container: container)
        sync = LibrarySync(client: client, store: store)
        sessions = SessionTracker(store: store, sync: sync)
        sync.onError = { [weak self] error in
            self?.handle(error)
        }
        sessions.onChange = { [weak self] session in
            self?.updateLiveActivity(session)
        }
        sessions.onEarned = { [weak self] trophies, _ in
            self?.celebrate(trophies)
        }
        sessions.onEnded = { [weak self] session in
            self?.endedSession = session
        }
        // A session left running by an earlier launch: its activity shows it again.
        updateLiveActivity(sessions.current)
    }

    // MARK: Sessions

    /// Starts a session in a game and opens its screen.
    func startSession(gameId: String) async {
        await sessions.start(gameId: gameId)
        isShowingSession = sessions.current != nil
    }

    func endSession() async {
        isShowingSession = false
        await sessions.end()
    }

    func celebrationShown() {
        celebration = nil
    }

    private func celebrate(_ trophies: [TrophyRecord]) {
        guard !trophies.isEmpty else { return }
        celebration = Celebration(
            trophyNames: trophies.map(\.name),
            isPlatinum: trophies.contains { $0.type == .platinum }
        )
    }

    private func updateLiveActivity(_ session: PlaySessionRecord?) {
        guard let session else {
            liveActivity.end()
            return
        }
        let game = try? store.game(session.gameId)
        let lastTrophy = sessions.lastEarned.last
        liveActivity.update(session: session, game: game, goals: sessions.goalTrophies(), lastTrophy: lastTrophy)
    }

    func start() async {
        phase = await client.isSignedIn ? .signedIn : .signedOut
    }

    func signIn(authorizationCode code: String) async throws {
        try await client.signIn(authorizationCode: code)
        didSignIn()
    }

    func signIn(npsso: String) async throws {
        try await client.signIn(npsso: npsso)
        didSignIn()
    }

    /// Signs out of PSN and forgets what PSN gave. The person's own plans stay on the device.
    func signOut() async {
        await sessions.end()
        try? await client.signOut()
        try? store.eraseCache()
        phase = .signedOut
    }

    /// Errors of loading: an expired session ends in the sign-in screen, everything else stays
    /// with the screen that loads.
    func handle(_ error: any Error) {
        if let error = error as? PSNError, error == .sessionExpired || error == .notSignedIn {
            signOutReason = error.userMessage
            phase = .signedOut
        }
    }

    private func didSignIn() {
        signOutReason = nil
        phase = .signedIn
    }
}

/// The language PSN answers in: the app's own (Russian or English).
enum AppLanguage {
    static var psnLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "ru"
        return code.hasPrefix("en") ? "en-US" : "ru-RU"
    }
}
