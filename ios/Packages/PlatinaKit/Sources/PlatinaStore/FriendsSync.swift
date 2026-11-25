#if canImport(SwiftData)
import Foundation
import Observation
import os
import PSNKit

private let log = Logger(subsystem: "dakacom.Platina", category: "Sync")

/// The person's PSN friends and their trophy lists, for comparing progress in shared games
/// (docs/superpowers/specs/2026-11-25-platina-1.1-design.md). Sony's request limits are spared:
/// a refresh happens when a friends screen opens and the lists are older than 12 hours, or on
/// pull to refresh; profiles are read again weekly; requests go one at a time.
@MainActor
@Observable
public final class FriendsSync {
    public enum Status: Equatable, Sendable {
        case idle
        case syncing
        case failed(PSNError)
    }

    public static let refreshInterval: TimeInterval = 12 * 3600
    public static let profileInterval: TimeInterval = 7 * 24 * 3600

    public private(set) var status: Status = .idle
    public private(set) var lastRefreshedAt: Date?

    /// Session errors go here, for the app to sign out.
    @ObservationIgnored public var onError: ((PSNError) -> Void)?

    private let client: PSNClient
    private let store: LibraryStore
    private let now: @Sendable () -> Date

    public init(client: PSNClient, store: LibraryStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
        // The oldest friend's lists say when the whole refresh last finished.
        lastRefreshedAt = (try? store.friends())?.compactMap(\.titlesUpdatedAt).min()
    }

    /// Reads the friends list, each friend's profile when it is a week old, and each friend's trophy
    /// lists. Without `force`, only when the last refresh is older than 12 hours.
    public func refresh(force: Bool = false) async {
        guard status != .syncing else { return }
        if !force, let lastRefreshedAt, now().timeIntervalSince(lastRefreshedAt) < Self.refreshInterval {
            return
        }
        status = .syncing
        do {
            let ids = try await client.friendIds()
            try store.keepFriends(ids)
            for id in ids {
                let profileDate = try store.friend(id)?.profileUpdatedAt
                if profileDate.map({ now().timeIntervalSince($0) >= Self.profileInterval }) ?? true {
                    // A profile PSN will not give (privacy, a closed account) leaves the friend
                    // nameless, not the whole list failed; a session or limit error stops.
                    do {
                        let profile = try await client.profile(accountId: id)
                        try store.saveFriendProfile(profile, accountId: id, at: now())
                    } catch let error as PSNError where !error.stopsFriendsSync {
                        log.error("Friend profile: \(String(describing: error), privacy: .public)")
                    }
                }
                let titles = try await client.trophyTitles(of: id)
                try store.saveFriendTitles(titles, accountId: id, at: now())
            }
            lastRefreshedAt = now()
            status = .idle
        } catch let error as PSNError {
            log.error("Friends: \(String(describing: error), privacy: .public)")
            status = .failed(error)
            onError?(error)
        } catch is CancellationError {
            // The screen that asked went away: the next visit asks again.
            status = .idle
        } catch {
            log.error("Friends: \(String(describing: error), privacy: .public)")
            status = .failed(.transport("\(error)"))
        }
    }

    /// After signing out.
    public func reset() {
        lastRefreshedAt = nil
        status = .idle
    }
}
private extension PSNError {
    /// The errors after which asking about the next friend is no use.
    var stopsFriendsSync: Bool {
        switch self {
        case .sessionExpired, .notSignedIn, .rateLimited, .offline: true
        default: false
        }
    }
}
#endif
