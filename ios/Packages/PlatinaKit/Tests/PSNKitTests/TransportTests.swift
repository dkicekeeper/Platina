#if canImport(Darwin)
import Foundation
import Testing
@testable import PSNKit

@Suite("Network errors")
struct TransportTests {
    private let request = URLRequest(url: URL(string: "https://m.np.playstation.com/api/trophy/v1/users/me/trophySummary")!)

    @Test("A cancelled request is a cancellation, not a failure")
    func cancelled() {
        #expect(URLSessionTransport.mapped(URLError(.cancelled), for: request) is CancellationError)
    }

    @Test("No connection on the phone is offline")
    func offline() {
        #expect(URLSessionTransport.mapped(URLError(.notConnectedToInternet), for: request) as? PSNError == .offline)
        #expect(URLSessionTransport.mapped(URLError(.dataNotAllowed), for: request) as? PSNError == .offline)
    }

    @Test("PSN not answering names the request and the code")
    func notAnswering() throws {
        let error = try #require(URLSessionTransport.mapped(URLError(.timedOut), for: request) as? PSNError)
        guard case .transport(let detail) = error else {
            Issue.record("expected a transport error, got \(error)")
            return
        }
        #expect(detail.contains("m.np.playstation.com/api/trophy/v1/users/me/trophySummary"))
        #expect(detail.contains("-1001"))
    }
}
#endif
