import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The PSN API for the signed-in person. Keeps the tokens fresh on its own: refreshes the access
/// token before it runs out, and once more when PSN answers 401. Concurrent requests share one
/// refresh.
public actor PSNClient {
    static let apiBase = URL(string: "https://m.np.playstation.com/api")!

    private let store: any PSNTokenStore
    private let transport: any HTTPTransport
    private let authenticator: PSNAuthenticator
    private let now: @Sendable () -> Date
    private var tokens: PSNTokens?
    private var refreshing: Task<PSNTokens, any Error>?
    /// The person's account id, from the trophy summary: the profile and presence endpoints
    /// answer 400 to `me`.
    private var accountId: String?

    /// `ru-RU` or `en-US`: the language of trophy names and descriptions.
    public var language: String

    public init(
        store: any PSNTokenStore,
        transport: any HTTPTransport,
        language: String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.language = language
        self.now = now
        authenticator = PSNAuthenticator(transport: transport, now: now)
        tokens = try? store.load()
    }

    // MARK: Session

    /// Signed in, and the refresh token has not run out yet.
    public var isSignedIn: Bool {
        guard let tokens else { return false }
        return tokens.refreshTokenExpiresAt > now()
    }

    /// When the person will have to sign in again.
    public var sessionExpiresAt: Date? { tokens?.refreshTokenExpiresAt }

    public func setLanguage(_ language: String) {
        self.language = language
    }

    /// Signs in with the code from Sony's redirect.
    public func signIn(authorizationCode code: String) async throws {
        accountId = nil
        try save(try await authenticator.tokens(fromAuthorizationCode: code))
    }

    /// Signs in with an NPSSO token.
    public func signIn(npsso: String) async throws {
        accountId = nil
        try save(try await authenticator.tokens(fromNPSSO: npsso))
    }

    public func signOut() throws {
        refreshing?.cancel()
        refreshing = nil
        tokens = nil
        accountId = nil
        try store.clear()
    }

    // MARK: Endpoints

    /// Every trophy list of the person, newest change first.
    public func trophyTitles() async throws -> [TrophyTitle] {
        try await allPages(TrophyTitlesPage.self, limit: 200) { limit, offset in
            ("trophy/v1/users/me/trophyTitles", [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ])
        }
    }

    /// The trophy level and totals.
    public func trophySummary() async throws -> TrophySummary {
        let summary: TrophySummary = try await get("trophy/v1/users/me/trophySummary")
        accountId = summary.accountId
        return summary
    }

    /// The online id and avatar. Without an account id, the person's own (from the trophy
    /// summary, asked first if no request brought it yet).
    public func profile(accountId: String? = nil) async throws -> PSNProfile {
        let id: String
        if let accountId {
            id = accountId
        } else {
            id = try await myAccountId()
        }
        return try await get("userProfile/v1/internal/users/\(id)/profiles")
    }

    /// The person's account id: the one the last trophy summary gave, or a summary's now.
    private func myAccountId() async throws -> String {
        if let accountId { return accountId }
        return try await trophySummary().accountId
    }

    /// The base game and DLC groups of a trophy list.
    public func trophyGroups(for title: TrophyTitle) async throws -> [TrophyGroup] {
        let response: TrophyGroupsResponse = try await get(
            "trophy/v1/npCommunicationIds/\(title.npCommunicationId)/trophyGroups",
            query: [URLQueryItem(name: "npServiceName", value: title.npServiceName)]
        )
        return response.trophyGroups
    }

    /// Every trophy of a list, base game and DLC, with the person's progress on each.
    public func trophies(for title: TrophyTitle) async throws -> [Trophy] {
        async let definitions = allPages(TrophyDefinitionsPage.self, limit: 500) { limit, offset in
            ("trophy/v1/npCommunicationIds/\(title.npCommunicationId)/trophyGroups/all/trophies", [
                URLQueryItem(name: "npServiceName", value: title.npServiceName),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ])
        }
        async let earnings = allPages(TrophyEarningsPage.self, limit: 500) { limit, offset in
            ("trophy/v1/users/me/npCommunicationIds/\(title.npCommunicationId)/trophyGroups/all/trophies", [
                URLQueryItem(name: "npServiceName", value: title.npServiceName),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ])
        }
        return Self.merge(definitions: try await definitions, earnings: try await earnings)
    }

    /// The person's progress in one game, without its trophies: whether anything changed.
    public func progress(for title: TrophyTitle) async throws -> TitleProgress {
        try await get(
            "trophy/v1/users/me/npCommunicationIds/\(title.npCommunicationId)/trophyGroups",
            query: [URLQueryItem(name: "npServiceName", value: title.npServiceName)]
        )
    }

    /// The person's side of every trophy of a game (earned, when, progress), without names and
    /// icons: what a session needs once the trophies are stored.
    public func earnings(for title: TrophyTitle) async throws -> [TrophyEarning] {
        try await allPages(TrophyEarningsPage.self, limit: 500) { limit, offset in
            ("trophy/v1/users/me/npCommunicationIds/\(title.npCommunicationId)/trophyGroups/all/trophies", [
                URLQueryItem(name: "npServiceName", value: title.npServiceName),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ])
        }
    }

    /// The games played on PS4 and PS5 with the time in each, most recent first.
    public func playedGames() async throws -> [PlayedGame] {
        try await allPages(PlayedGamesPage.self, limit: 200) { limit, offset in
            ("gamelist/v2/users/me/titles", [
                URLQueryItem(name: "categories", value: "ps4_game,ps5_native_game"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset)),
            ])
        }
    }

    /// The trophy lists of game titles (`PPSA…_00`), five titles a request.
    public func trophyLinks(forTitleIds titleIds: [String]) async throws -> [TitleTrophyLink] {
        var links: [TitleTrophyLink] = []
        for start in stride(from: 0, to: titleIds.count, by: 5) {
            let chunk = titleIds[start..<min(start + 5, titleIds.count)]
            let response: TitleTrophyLinksResponse = try await get(
                "trophy/v1/users/me/titles/trophyTitles",
                query: [URLQueryItem(name: "npTitleIds", value: chunk.joined(separator: ","))]
            )
            links += response.titles
        }
        return links
    }

    /// What is running on the console now.
    public func presence() async throws -> Presence {
        let id = try await myAccountId()
        let response: PresenceResponse = try await get(
            "userProfile/v1/internal/users/\(id)/basicPresences",
            query: [URLQueryItem(name: "type", value: "primary")]
        )
        return response.presence
    }

    // MARK: Requests

    static func merge(definitions: [TrophyDefinition], earnings: [TrophyEarning]) -> [Trophy] {
        let byId = Dictionary(earnings.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        return definitions.map { Trophy(definition: $0, earning: byId[$0.trophyId]) }
    }

    private func allPages<Page: PSNPage>(
        _ type: Page.Type,
        limit: Int,
        request: @Sendable (Int, Int) -> (String, [URLQueryItem])
    ) async throws -> [Page.Item] {
        var items: [Page.Item] = []
        var offset = 0
        while true {
            let (path, query) = request(limit, offset)
            let page: Page = try await get(path, query: query)
            items += page.items
            guard let next = page.nextOffset, next > offset, !page.items.isEmpty, items.count < page.totalItemCount else {
                return items
            }
            offset = next
        }
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], headers: [String: String] = [:]) async throws -> T {
        let data = try await send(path: path, query: query, headers: headers, retryOnUnauthorized: true)
        do {
            return try JSONDecoder.psn.decode(T.self, from: data)
        } catch {
            PSNLog.failure("GET \(path): could not read the answer: \(error)")
            throw PSNError.decoding("\(path): \(error)")
        }
    }

    private func send(path: String, query: [URLQueryItem], headers: [String: String], retryOnUnauthorized: Bool) async throws -> Data {
        let token = try await accessToken()
        var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(language, forHTTPHeaderField: "Accept-Language")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpShouldHandleCookies = false

        let (data, response) = try await transport.send(request, followRedirects: true)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401 where retryOnUnauthorized:
            _ = try await refreshedTokens(force: true)
            return try await send(path: path, query: query, headers: headers, retryOnUnauthorized: false)
        case 401:
            throw PSNError.sessionExpired
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw PSNError.rateLimited(retryAfter: retryAfter)
        default:
            let body = try? JSONDecoder().decode(PSNErrorBody.self, from: data)
            PSNLog.failure("GET \(path): HTTP \(response.statusCode) \(body?.error.code.map(String.init) ?? "") \(body?.error.message ?? "")")
            throw PSNError.http(status: response.statusCode, code: body?.error.code, message: body?.error.message)
        }
    }

    /// A valid access token, refreshed first when it runs out within a minute.
    private func accessToken() async throws -> String {
        guard let tokens else { throw PSNError.notSignedIn }
        if tokens.accessTokenExpires(within: 60, at: now()) {
            return try await refreshedTokens(force: false).accessToken
        }
        return tokens.accessToken
    }

    private func refreshedTokens(force: Bool) async throws -> PSNTokens {
        if let refreshing {
            return try await refreshing.value
        }
        guard let current = tokens else { throw PSNError.notSignedIn }
        if !force, !current.accessTokenExpires(within: 60, at: now()) {
            return current
        }
        guard current.refreshTokenExpiresAt > now() else {
            try? signOut()
            throw PSNError.sessionExpired
        }
        let authenticator = authenticator
        let task = Task { try await authenticator.refresh(current.refreshToken) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            try save(fresh)
            return fresh
        } catch PSNError.sessionExpired {
            try? signOut()
            throw PSNError.sessionExpired
        }
    }

    private func save(_ tokens: PSNTokens) throws {
        self.tokens = tokens
        try store.save(tokens)
    }
}
