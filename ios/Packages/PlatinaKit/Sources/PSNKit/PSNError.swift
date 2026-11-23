import Foundation

/// What can go wrong talking to PSN. The app turns each case into its own words.
public enum PSNError: Error, Sendable, Equatable {
    /// No tokens: the person has not signed in, or signed out.
    case notSignedIn
    /// The refresh token expired or was revoked: sign in again.
    case sessionExpired
    /// Sony did not accept the NPSSO token (wrong, expired, or the session behind it ended).
    case invalidNPSSO
    /// Sony's sign-in answered something unexpected.
    case authorizationFailed(String)
    /// PSN answered with an error status. `code` and `message` come from its error body.
    case http(status: Int, code: Int?, message: String?)
    /// Too many requests: wait before the next sync.
    case rateLimited(retryAfter: TimeInterval?)
    /// The answer could not be read: PSN changed its format, or a field we rely on is missing.
    case decoding(String)
    /// The phone has no connection to the internet.
    case offline
    /// PSN did not answer: a timeout, no way to its server, a broken secure connection. The text
    /// says which request and why, for the log.
    case transport(String)
}

/// PSN's error body: `{"error":{"referenceId":"…","code":2240526,"message":"…"}}`.
struct PSNErrorBody: Decodable {
    struct Detail: Decodable {
        let code: Int?
        let message: String?
    }

    let error: Detail
}

/// The OAuth server's error body: `{"error":"invalid_grant","error_description":"…"}`.
struct OAuthErrorBody: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
