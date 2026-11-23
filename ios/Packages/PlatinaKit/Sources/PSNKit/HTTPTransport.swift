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

    /// Sends the request; when it fails the way a wrong DNS answer makes it fail, switches the
    /// app's name resolution (`NameResolution`) and sends it once more.
    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let resolution = NameResolution.shared
        let turn = await resolution.turn
        do {
            let result = try await attempt(request, followRedirects: followRedirects)
            await resolution.succeeded(inTurn: turn)
            return result
        } catch let error as URLError where NameResolution.isWrongAddressLike(error) {
            PSNLog.failure("\(Self.target(of: request)): URLError \(error.code.rawValue), trying the other name resolution")
            await resolution.failed(inTurn: turn)
            let retryTurn = await resolution.turn
            do {
                let result = try await attempt(request, followRedirects: followRedirects)
                await resolution.succeeded(inTurn: retryTurn)
                return result
            } catch let error as URLError {
                throw Self.mapped(error, for: request)
            }
        } catch let error as URLError {
            throw Self.mapped(error, for: request)
        }
    }

    private func attempt(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let delegate: (any URLSessionTaskDelegate)? = followRedirects ? nil : NoRedirectDelegate()
        let (data, response) = try await session.data(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else {
            throw PSNError.transport("Not an HTTP response")
        }
        return (data, http)
    }

    private static func target(of request: URLRequest) -> String {
        "\(request.httpMethod ?? "GET") \(request.url?.host ?? "")\(request.url?.path ?? "")"
    }

    /// A cancelled request is the caller's own doing, not a failure; no connection on the phone
    /// is told apart from PSN not answering.
    static func mapped(_ error: URLError, for request: URLRequest) -> any Error {
        if error.code == .cancelled {
            return CancellationError()
        }
        let described = Self.target(of: request)
        PSNLog.failure("\(described): URLError \(error.code.rawValue) \(error.localizedDescription)")
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return PSNError.offline
        default:
            return PSNError.transport("\(described): URLError \(error.code.rawValue)")
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
