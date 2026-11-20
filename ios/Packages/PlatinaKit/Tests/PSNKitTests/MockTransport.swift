import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PSNKit

/// Answers requests from a handler and keeps every request it got.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int = 200
        var body: Data = Data()
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var handler: @Sendable (URLRequest) throws -> Reply
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping @Sendable (URLRequest) throws -> Reply) {
        self.handler = handler
    }

    var requestCount: Int { lock.withLock { requests.count } }

    func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let handler = lock.withLock {
            requests.append(request)
            return self.handler
        }
        let reply = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }
}

struct FixtureMissing: Error {
    let name: String
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureMissing(name: name)
        }
        return try Data(contentsOf: url)
    }

    static func reply(_ name: String) throws -> MockTransport.Reply {
        MockTransport.Reply(body: try data(name))
    }
}

extension URLRequest {
    var queryItems: [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    var formFields: [String: String] {
        let body = httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }
}

let validTokens = PSNTokens(
    accessToken: "access-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 2_000_000_000),
    refreshToken: "refresh-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 2_100_000_000)
)

let fixedNow = Date(timeIntervalSince1970: 1_999_000_000)

func tokenResponse(access: String, refresh: String) -> MockTransport.Reply {
    let json = """
    {"access_token":"\(access)","token_type":"bearer","expires_in":3599,"scope":"psn:mobile.v2.core psn:clientapp",\
    "id_token":"id","refresh_token":"\(refresh)","refresh_token_expires_in":5183999}
    """
    return MockTransport.Reply(body: Data(json.utf8))
}
