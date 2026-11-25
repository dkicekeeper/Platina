#if canImport(Darwin)
import Foundation

/// Trophy notifications on Plati's server (docs/assistant.md §9): turn on with an authorization
/// code the app asked Sony for (the server exchanges it for its own tokens), a new device token,
/// turn off. Every body is signed, as the builds are.
public final class TrophyAlertsClient: @unchecked Sendable {
    /// Where APNs delivers: Xcode's builds to the sandbox, TestFlight and the App Store to production.
    public enum Environment: String, Sendable {
        case sandbox, production
    }

    private let baseURL: URL
    private let session: URLSession
    private let signer: (any AssistantSigner)?

    public init(baseURL: URL, signer: (any AssistantSigner)?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.signer = signer
        self.session = session
    }

    /// Turns the notifications on, or renews the server's grant after a new sign-in.
    /// `invalidRequest(reason: "code")`: Sony did not take the code (sign in again).
    public func subscribe(code: String, pushToken: String, environment: Environment, language: String) async throws {
        try await send("POST", path: "v1/alerts", body: [
            "code": code, "pushToken": pushToken, "environment": environment.rawValue, "language": language,
        ])
    }

    /// The device token changed (or the app checks in). False: the server no longer watches for
    /// this install (it stopped after Sony refused its grant, or was turned off).
    public func updateToken(_ pushToken: String, environment: Environment) async throws -> Bool {
        do {
            try await send("PUT", path: "v1/alerts/token", body: ["pushToken": pushToken, "environment": environment.rawValue])
            return true
        } catch let error as AssistantServerError where error == .http(status: 404) {
            return false
        }
    }

    /// Turns the notifications off: the server forgets its grant and everything else.
    public func unsubscribe() async throws {
        try await send("DELETE", path: "v1/alerts", body: [:])
    }

    private func send(_ method: String, path: String, body: [String: String]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        do {
            try await attempt(method, path: path, body: data)
        } catch let error as AssistantServerError where error == .attestation(reason: "unknown_key") {
            // The server forgot the key: a new one, once.
            await signer?.reset()
            try await attempt(method, path: path, body: data)
        }
    }

    private func attempt(_ method: String, path: String, body: Data) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let signer {
            for (name, value) in try await signer.headers(for: body) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AssistantServerError.from(status: status, body: data) }
    }
}
#endif
