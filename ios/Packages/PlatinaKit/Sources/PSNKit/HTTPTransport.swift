import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request. The client and the authenticator talk to PSN only through it, so
/// tests can answer with fixtures and no request leaves the machine.
public protocol HTTPTransport: Sendable {
    /// - Parameter followRedirects: `false` returns a 3xx response as it is (the sign-in reads
    ///   the authorization code from its `Location` header).
    func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse)
}

#if canImport(Darwin)
/// The transport the app uses: an ephemeral `URLSession`, so Sony's cookies never land in the
/// shared cookie storage.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let delegate: (any URLSessionTaskDelegate)? = followRedirects ? nil : NoRedirectDelegate()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch let error as URLError {
            throw Self.mapped(error, for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PSNError.transport("Not an HTTP response")
        }
        return (data, http)
    }

    /// A cancelled request is the caller's own doing, not a failure; no connection on the phone
    /// is told apart from PSN not answering.
    static func mapped(_ error: URLError, for request: URLRequest) -> any Error {
        if error.code == .cancelled {
            return CancellationError()
        }
        let target = "\(request.httpMethod ?? "GET") \(request.url?.host ?? "")\(request.url?.path ?? "")"
        PSNLog.failure("\(target): URLError \(error.code.rawValue) \(error.localizedDescription)")
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return PSNError.offline
        default:
            return PSNError.transport("\(target): URLError \(error.code.rawValue)")
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
#endif
