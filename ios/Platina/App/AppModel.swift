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

    init(container: ModelContainer, client: PSNClient? = nil) {
        let client = client ?? PSNClient(
            store: KeychainTokenStore(service: "dakacom.Platina.psn"),
            transport: URLSessionTransport(),
            language: AppLanguage.psnLanguage
        )
        self.client = client
        store = LibraryStore(container: container)
        sync = LibrarySync(client: client, store: store)
        sync.onError = { [weak self] error in
            self?.handle(error)
        }
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
