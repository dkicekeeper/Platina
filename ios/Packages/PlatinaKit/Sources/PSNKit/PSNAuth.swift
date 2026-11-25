import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sony's OAuth constants: the ones the PlayStation App uses, as every PSN client does
/// (psn-api, PSNAWP). docs/PLAN.md §2.
public enum PSNAuth {
    static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    /// `clientID:clientSecret` in Base64, as the PlayStation App sends it.
    static let basicAuthorization =
        "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
    public static let redirectScheme = "com.scee.psxandroid.scecompcall"
    static let redirectURI = "\(redirectScheme)://redirect"
    static let scope = "psn:mobile.v2.core psn:clientapp"
    static let oauthBase = URL(string: "https://ca.account.sony.com/api/authz/v3/oauth")!

    /// Where the person gets their NPSSO token by hand, after signing in on playstation.com.
    public static let ssoCookieURL = URL(string: "https://ca.account.sony.com/api/v1/ssocookie")!

    /// Where the person signs in for the manual way: the PlayStation Store, as psn-api and
    /// andshrew's API notes advise; after signing in on playstation.com Safari may hold no
    /// `npsso` for the ssocookie page, after the store it does. The US store, not the bare
    /// address: that redirects by country, and a country without a region of its own
    /// (Kazakhstan) lands on a 404.
    public static let webSignInURL = URL(string: "https://store.playstation.com/en-us/")!

    /// The PlayStation Store's own sign-in, what its "Sign In" button opens: Sony's sign-in page
    /// for the web client, which loads where the PlayStation App client's page does not (§2 of
    /// docs/PLAN.md). Its session service takes only playstation.com addresses to return to.
    public static let storeSignInURL = URL(
        string: "https://web.np.playstation.com/api/session/v1/signin?redirect_uri=https%3A%2F%2Fstore.playstation.com%2Fen-us%2Fpages%2Flatest"
    )!

    /// Whether the store's sign-in is over: Sony sends the browser back to the session service
    /// with a code for the web client (`web.np.playstation.com/api/session/v1/session?code=…`),
    /// or on to the store. By then Sony's own session (the `npsso` cookie) is set.
    public static func isStoreSignInFinished(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "web.np.playstation.com" {
            return url.path.hasSuffix("/session/v1/session")
        }
        return host == "store.playstation.com"
    }

    /// The PlayStation App client's authorization: with Sony's session (the `npsso` cookie) it
    /// redirects straight to `com.scee.psxandroid.scecompcall://redirect/?code=…`, which is how an
    /// NPSSO token becomes the app's code. Its sign-in page, shown without a session, does not
    /// load for some people: the app signs in through the store (`storeSignInURL`) instead.
    public static var authorizeURL: URL {
        var components = URLComponents(url: oauthBase.appendingPathComponent("authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
        ]
        return components.url!
    }

    /// The authorization code from Sony's redirect (`…://redirect/?code=v3.XXXX&cid=…`), or nil
    /// when the redirect carries no code (`?error=login_required`).
    public static func authorizationCode(fromRedirect url: URL) -> String? {
        authorizationCode(fromRedirect: url.absoluteString)
    }

    static func authorizationCode(fromRedirect location: String) -> String? {
        guard let query = location.split(separator: "?", maxSplits: 1).last, location.contains("?") else {
            return nil
        }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == "code" {
                let code = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                return code.isEmpty ? nil : code
            }
        }
        return nil
    }

    /// Whether a URL is Sony's redirect back to the app (with a code or with an error).
    public static func isRedirect(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectScheme
    }

    /// An NPSSO token as the person pasted it: the bare 64 characters, or the whole
    /// `{"npsso":"…"}` answer of the ssocookie page.
    public static func normalizedNPSSO(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONDecoder().decode([String: String].self, from: data),
           let token = object["npsso"] {
            return normalizedNPSSO(token)
        }
        let allowed = CharacterSet.alphanumerics
        guard trimmed.count >= 32, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

/// Exchanges what the sign-in produced (an authorization code or an NPSSO token) for tokens,
/// and refreshes them.
public struct PSNAuthenticator: Sendable {
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    public init(transport: any HTTPTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    /// Tokens for the code from Sony's redirect.
    public func tokens(fromAuthorizationCode code: String) async throws -> PSNTokens {
        try await requestTokens([
            ("code", code),
            ("redirect_uri", PSNAuth.redirectURI),
            ("grant_type", "authorization_code"),
            ("token_format", "jwt"),
        ])
    }

    /// Tokens for an NPSSO token: the manual sign-in.
    public func tokens(fromNPSSO npsso: String) async throws -> PSNTokens {
        let code = try await authorizationCode(fromNPSSO: npsso)
        return try await tokens(fromAuthorizationCode: code)
    }

    /// New tokens for a refresh token. Throws `.sessionExpired` when Sony no longer accepts it.
    public func refresh(_ refreshToken: String) async throws -> PSNTokens {
        try await requestTokens([
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
            ("token_format", "jwt"),
            ("scope", PSNAuth.scope),
        ])
    }

    /// An authorization code for an NPSSO token: the sign-in's step before the tokens. Trophy
    /// notifications ask for a second one and hand only it to Plati's server, which exchanges
    /// it for tokens of its own (docs/assistant.md §9).
    public func authorizationCode(fromNPSSO npsso: String) async throws -> String {
        var request = URLRequest(url: PSNAuth.authorizeURL)
        request.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
        let (_, response) = try await transport.send(request, followRedirects: false)
        guard let location = response.value(forHTTPHeaderField: "Location") else {
            throw PSNError.invalidNPSSO
        }
        guard let code = PSNAuth.authorizationCode(fromRedirect: location) else {
            throw PSNError.invalidNPSSO
        }
        return code
    }

    private func requestTokens(_ fields: [(String, String)]) async throws -> PSNTokens {
        var request = URLRequest(url: PSNAuth.oauthBase.appendingPathComponent("token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(PSNAuth.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.httpShouldHandleCookies = false
        request.httpBody = FormEncoding.encode(fields).data(using: .utf8)

        let requestedAt = now()
        let (data, response) = try await transport.send(request, followRedirects: true)
        guard (200..<300).contains(response.statusCode) else {
            let oauth = try? JSONDecoder().decode(OAuthErrorBody.self, from: data)
            if response.statusCode == 400 || response.statusCode == 401, oauth?.error == "invalid_grant" {
                throw PSNError.sessionExpired
            }
            throw PSNError.authorizationFailed(oauth?.errorDescription ?? oauth?.error ?? "HTTP \(response.statusCode)")
        }
        do {
            let body = try JSONDecoder().decode(TokenResponse.self, from: data)
            return PSNTokens(
                accessToken: body.accessToken,
                accessTokenExpiresAt: requestedAt.addingTimeInterval(TimeInterval(body.expiresIn)),
                refreshToken: body.refreshToken,
                refreshTokenExpiresAt: requestedAt.addingTimeInterval(TimeInterval(body.refreshTokenExpiresIn))
            )
        } catch {
            throw PSNError.decoding("token response: \(error)")
        }
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String
    let refreshTokenExpiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
    }
}

/// `application/x-www-form-urlencoded`, as `URLSearchParams` writes it (a space is `+`).
enum FormEncoding {
    private static let unreserved = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")

    static func encode(_ fields: [(String, String)]) -> String {
        fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    static func escape(_ value: String) -> String {
        value
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? String($0) }
            .joined(separator: "+")
    }
}
