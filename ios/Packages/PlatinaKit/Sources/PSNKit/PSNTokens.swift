import Foundation
#if canImport(Security)
import Security
#endif

/// The tokens of a signed-in PSN account. The access token lives about an hour, the refresh
/// token about two months.
public struct PSNTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var accessTokenExpiresAt: Date
    public var refreshToken: String
    public var refreshTokenExpiresAt: Date

    public init(accessToken: String, accessTokenExpiresAt: Date, refreshToken: String, refreshTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }

    /// The access token runs out within `margin` (a request takes a moment).
    func accessTokenExpires(within margin: TimeInterval, at date: Date) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(date) < margin
    }
}

/// Where the tokens are kept between launches.
public protocol PSNTokenStore: Sendable {
    func load() throws -> PSNTokens?
    func save(_ tokens: PSNTokens) throws
    func clear() throws
}

/// Tokens in memory only: tests and previews.
public final class InMemoryTokenStore: PSNTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: PSNTokens?

    public init(_ tokens: PSNTokens? = nil) {
        self.tokens = tokens
    }

    public func load() throws -> PSNTokens? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: PSNTokens) throws {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() throws {
        lock.withLock { tokens = nil }
    }
}

#if canImport(Security)
/// The tokens in the Keychain, on this device only, readable after the first unlock (the
/// background sync runs while the phone is locked).
public struct KeychainTokenStore: PSNTokenStore {
    private let service: String
    private let account = "psn-tokens"

    public init(service: String) {
        self.service = service
    }

    public func load() throws -> PSNTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(PSNTokens.self, from: data)
    }

    public func save(_ tokens: PSNTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}
#endif
