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
            throw PSNError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PSNError.transport("Not an HTTP response")
        }
        return (data, http)
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
