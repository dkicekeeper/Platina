import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AssistantServerError: Error, Equatable {
    case notConfigured
    case invalidRequest(reason: String?)
    case quotaExceeded
    case regionUnavailable
    case disabled
    /// App Attest was missing or refused (`reason` from the server, or "unsupported").
    case attestation(reason: String?)
    case http(status: Int)

    private struct Body: Decodable {
        let error: String
        let reason: String?
    }

    public static func from(status: Int, body: Data) -> AssistantServerError {
        let parsed = try? JSONDecoder().decode(Body.self, from: body)
        switch status {
        case 400: return parsed?.error == "attestation" ? .attestation(reason: parsed?.reason) : .invalidRequest(reason: parsed?.reason)
        case 401: return .attestation(reason: parsed?.reason)
        case 429: return .quotaExceeded
        case 451: return .regionUnavailable
        case 503: return .disabled
        default: return .http(status: status)
        }
    }
}

/// Where the server lives: Info.plist's `PlatinaAssistantHost` (from ios/Config/Platina.xcconfig,
/// `PLATINA_ASSISTANT_HOST`, a host without "https://": an xcconfig reads `//` as a comment).
/// Empty: Plati is off and its tab says the server is not set up.
public enum AssistantConfig {
    public static var serverURL: URL? {
        url(host: Bundle.main.object(forInfoDictionaryKey: "PlatinaAssistantHost") as? String)
    }

    static func url(host raw: String?) -> URL? {
        guard var host = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else { return nil }
        if host.hasPrefix("https://") { host.removeFirst("https://".count) }
        while host.hasSuffix("/") { host.removeLast() }
        guard !host.isEmpty, !host.contains("$(") else { return nil }
        return URL(string: "https://\(host)")
    }

    /// Debug only: lets the Simulator in without App Attest (`DEV_TOKEN` on the server).
    public static var devToken: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PlatinaAssistantDevToken") as? String,
              !raw.isEmpty, !raw.contains("$(") else { return nil }
        return raw
    }
}

/// Signs a request body: App Attest on a device, the dev token in the Simulator.
public protocol AssistantSigner: Sendable {
    func headers(for body: Data) async throws -> [String: String]
    /// The server did not know the key: make a new one.
    func reset() async
}

public struct DevTokenSigner: AssistantSigner {
    let token: String

    public init(token: String) {
        self.token = token
    }

    public func headers(for body: Data) async throws -> [String: String] {
        ["x-platina-dev": token]
    }

    public func reset() async {}
}

#if canImport(Darwin)
/// Calls the Worker (docs/assistant.md): `POST /v1/turn` and `POST /v1/guide` as server-sent
/// events, `GET /v1/guide/{id}` for a guide already built. Every body is signed.
public final class AssistantServerClient: AssistantTransport, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let signer: (any AssistantSigner)?

    public init(baseURL: URL, signer: (any AssistantSigner)?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.signer = signer
        self.session = session
    }

    public func turn(_ request: AssistantTurnRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        stream(path: "v1/turn", body: request) { AssistantStreamEvent($0) }
    }

    public func guide(_ request: GuideRequest) -> AsyncThrowingStream<GuideStreamEvent, Error> {
        stream(path: "v1/guide", body: request) { GuideStreamEvent($0) }
    }

    public func cachedGuide(gameId: String, language: String) async throws -> Guide? {
        var components = URLComponents(url: baseURL.appending(path: "v1/guide/\(gameId)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "language", value: language)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw AssistantServerError.from(status: status, body: data) }
        return try JSONDecoder().decode(Guide.self, from: data)
    }

    private func stream<Body: Encodable, Event: Sendable>(
        path: String,
        body: Body,
        decode: @escaping @Sendable (SSEParser.Event) -> Event?
    ) -> AsyncThrowingStream<Event, Error> {
        let baseURL = baseURL, session = session, signer = signer
        let encoded = Result { try JSONEncoder().encode(body) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let data = try encoded.get()
                    var bytes = try await Self.send(data, path: path, baseURL: baseURL, session: session, signer: signer)
                    if case .failure(let error) = bytes, error == .attestation(reason: "unknown_key"), let signer {
                        // The server lost the key (or never had it): register a new one, once.
                        await signer.reset()
                        bytes = try await Self.send(data, path: path, baseURL: baseURL, session: session, signer: signer)
                    }
                    let stream = try bytes.get()
                    var parser = SSEParser()
                    for try await line in stream.lines {
                        if let event = parser.feed(line: line), let decoded = decode(event) {
                            continuation.yield(decoded)
                        }
                    }
                    if let event = parser.finish(), let decoded = decode(event) {
                        continuation.yield(decoded)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func send(
        _ body: Data,
        path: String,
        baseURL: URL,
        session: URLSession,
        signer: (any AssistantSigner)?
    ) async throws -> Result<URLSession.AsyncBytes, AssistantServerError> {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        // A guide searches the web and writes for a minute or two.
        request.timeoutInterval = 240
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = body
        if let signer {
            for (name, value) in try await signer.headers(for: body) {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 16_384 { break }
            }
            return .failure(AssistantServerError.from(status: status, body: data))
        }
        return .success(bytes)
    }
}
#endif
