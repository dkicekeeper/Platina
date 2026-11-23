#if canImport(Network)
import Foundation
@preconcurrency import Network

/// How the app finds PSN's servers. Some networks' DNS hands a wrong address for
/// `m.np.playstation.com`: a server that drops the TLS handshake (`URLError -1200`), while the
/// same phone on another network gets through. The app starts with the system's resolver; when a
/// request fails the way a wrong address makes it fail, it switches the whole app to its own
/// encrypted DNS (Google's DNS over HTTPS, which asks Akamai with the person's region) and
/// retries, and switches back the same way when that fails. The mode that last worked is the one
/// the next launch starts with.
actor NameResolution {
    enum Mode: String, Sendable {
        case system
        case encrypted
    }

    static let defaultsKey = "psn.nameResolution"

    static let shared = NameResolution(
        initial: Mode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system,
        apply: applyToApp,
        remember: { UserDefaults.standard.set($0.rawValue, forKey: defaultsKey) }
    )

    private(set) var mode: Mode
    /// Grows with every switch: a request that failed before someone else switched does not
    /// switch back.
    private(set) var turn = 0
    private var remembered: Mode
    private let apply: @Sendable (Mode) -> Void
    private let remember: @Sendable (Mode) -> Void

    init(initial: Mode, apply: @escaping @Sendable (Mode) -> Void, remember: @escaping @Sendable (Mode) -> Void) {
        mode = initial
        remembered = initial
        self.apply = apply
        self.remember = remember
        apply(initial)
    }

    /// A request sent in `turn` failed the way a wrong address makes it fail: the other mode,
    /// unless another request already switched since.
    func failed(inTurn failedTurn: Int) {
        guard failedTurn == turn else { return }
        mode = mode == .system ? .encrypted : .system
        turn += 1
        apply(mode)
        PSNLog.failure("Name resolution: switched to \(mode.rawValue)")
    }

    /// A request sent in `turn` went through: its mode is the one to start with next time.
    func succeeded(inTurn succeededTurn: Int) {
        guard succeededTurn == turn, mode != remembered else { return }
        remembered = mode
        remember(mode)
    }

    /// The failures a wrong address causes: no answer, a refused or dropped connection, a broken
    /// handshake, a certificate for another name. Not "offline", not a cancellation.
    static func isWrongAddressLike(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut, .networkConnectionLost:
            true
        default:
            false
        }
    }

    /// The app's default privacy context: every connection of the app, `URLSession` too, resolves
    /// names this way from now on.
    private static func applyToApp(_ mode: Mode) {
        let resolver = NWParameters.PrivacyContext.ResolverConfiguration.https(
            URL(string: "https://dns.google/dns-query")!,
            serverAddresses: [
                .hostPort(host: "8.8.8.8", port: 443),
                .hostPort(host: "8.8.4.4", port: 443),
                .hostPort(host: "2001:4860:4860::8888", port: 443),
                .hostPort(host: "2001:4860:4860::8844", port: 443),
            ]
        )
        NWParameters.PrivacyContext.default.requireEncryptedNameResolution(
            mode == .encrypted,
            fallbackResolver: mode == .encrypted ? resolver : nil
        )
    }
}
#endif
