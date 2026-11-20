import Foundation
import Observation
import PSNKit

/// The app's session: signed in to PSN or not, and the client every screen loads through.
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

    init(client: PSNClient? = nil) {
        self.client = client ?? PSNClient(
            store: KeychainTokenStore(service: "dakacom.Platina.psn"),
            transport: URLSessionTransport(),
            language: AppLanguage.psnLanguage
        )
    }

    func start() async {
        phase = await client.isSignedIn ? .signedIn : .signedOut
    }

    func signIn(authorizationCode code: String) async throws {
        try await client.signIn(authorizationCode: code)
        signOutReason = nil
        phase = .signedIn
    }

    func signIn(npsso: String) async throws {
        try await client.signIn(npsso: npsso)
        signOutReason = nil
        phase = .signedIn
    }

    func signOut() async {
        try? await client.signOut()
        phase = .signedOut
    }

    /// Every screen passes its loading errors here: an expired session ends in the sign-in
    /// screen, everything else stays with the screen.
    func handle(_ error: any Error) {
        if let error = error as? PSNError, error == .sessionExpired || error == .notSignedIn {
            signOutReason = error.userMessage
            phase = .signedOut
        }
    }
}

/// The language PSN answers in: the app's own (Russian or English).
enum AppLanguage {
    static var psnLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "ru"
        return code.hasPrefix("en") ? "en-US" : "ru-RU"
    }
}
