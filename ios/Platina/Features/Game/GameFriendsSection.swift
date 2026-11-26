import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// The friends who play a game, and the person among them, the furthest first: a ring of
/// progress each, platinum-coloured once they have the platinum. A tap opens the friend.
///
/// The friend's screen is pushed by `GameView`, not here: this section lives inside
/// `AdaptiveColumns`, whose `ViewThatFits` builds both layouts, and a `navigationDestination` in
/// there froze the app when the game itself had been pushed (from the Path, 2026-11-26).
struct GameFriendsSection: View {
    let game: GameRecord
    /// Beside the trophies on a wide screen: a header and the first few; under the chips, all.
    var limit: Int?
    /// A friend was tapped: their account id.
    let onOpenFriend: (String) -> Void

    @Environment(AppModel.self) private var app
    @Query private var titles: [FriendTitleRecord]
    @Query private var friends: [FriendRecord]
    @Query private var profiles: [ProfileRecord]

    init(game: GameRecord, limit: Int? = nil, onOpenFriend: @escaping (String) -> Void) {
        self.game = game
        self.limit = limit
        self.onOpenFriend = onOpenFriend
        let id = game.id
        _titles = Query(filter: #Predicate<FriendTitleRecord> { $0.gameId == id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if limit != nil {
                SectionHeader(GameSection.friends.title, systemImage: GameSection.friends.systemImage)
            }
            content
        }
        .task { await app.friends.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        let entries = ranking
        if entries.count > 1 {
            let shown = limit.map { Array(entries.prefix($0)) } ?? entries
            CardList(shown, layout: .section, onOpen: { entry in
                if case .friend(let friend, _) = entry { onOpenFriend(friend.accountId) }
            }) { (entry: Entry) in
                EntryRow(entry: entry)
            }
        } else if friends.isEmpty, app.friends.status == .syncing {
            CardListSkeleton(layout: .section, count: 3)
        } else {
            EmptyState(
                icon: "person.2",
                title: String(localized: "game.friends.empty.title"),
                description: String(localized: "game.friends.empty.message"),
                style: limit == nil ? .standard : .compact
            )
        }
    }

    /// The person and every friend with the game, the furthest first; the person first in a tie.
    private var ranking: [Entry] {
        let byId = Dictionary(friends.map { ($0.accountId, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [Entry] = [.me(profiles.first, game)]
        for title in titles {
            guard let friend = byId[title.friendId], !friend.isHidden else { continue }
            entries.append(.friend(friend, title))
        }
        return entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.progress != rhs.element.progress
                    ? lhs.element.progress > rhs.element.progress
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// A row of the ranking.
    enum Entry: Identifiable {
        case me(ProfileRecord?, GameRecord)
        case friend(FriendRecord, FriendTitleRecord)

        var id: String {
            switch self {
            case .me: "me"
            case .friend(let friend, _): friend.accountId
            }
        }

        var progress: Int {
            switch self {
            case .me(_, let game): game.progress
            case .friend(_, let title): title.progress
            }
        }

        var hasPlatinum: Bool {
            switch self {
            case .me(_, let game): game.isPlatinumEarned
            case .friend(_, let title): title.hasPlatinum
            }
        }

        var earned: Int {
            switch self {
            case .me(_, let game): game.earned.total
            case .friend(_, let title): title.earnedTotal
            }
        }
    }
}

/// The person or a friend: the picture, the name, the trophies earned, the ring.
private struct EntryRow: View {
    let entry: GameFriendsSection.Entry

    var body: some View {
        PersonRow(name: name, subtitle: String(localized: "game.friends.trophies \(entry.earned)"), avatar: avatar) {
            GameProgressRing(progress: entry.progress, isPlatinum: entry.hasPlatinum)
        }
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        switch entry {
        case .me: String(localized: "friend.you")
        case .friend(let friend, _): friend.displayName
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch entry {
        case .me(let profile, _):
            RemotePhoto(key: "avatar-\(profile?.accountId ?? "me")", url: profile?.avatarURL)
                .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                .clipShape(Circle())
                .accessibilityHidden(true)
        case .friend(let friend, _):
            FriendAvatar(friend: friend)
        }
    }
}
