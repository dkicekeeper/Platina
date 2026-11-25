import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// The person's PSN friends and where they stand against each one in the games they share
/// (docs/superpowers/specs/2026-11-25-platina-1.1-design.md): progress only.
struct FriendsView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \FriendRecord.onlineId) private var friends: [FriendRecord]
    @Query private var games: [GameRecord]
    @Query private var titles: [FriendTitleRecord]
    @State private var openedFriend: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                content
            }
            .screenPadding()
            .readableWidth()
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.Background.base)
        .navigationTitle(Text("friends.title"))
        .refreshable { await app.friends.refresh(force: true) }
        .task { await app.friends.refresh() }
        .navigationDestination(item: $openedFriend) { accountId in
            FriendView(accountId: accountId)
        }
    }

    @ViewBuilder
    private var content: some View {
        if friends.isEmpty {
            switch app.friends.status {
            case .syncing:
                CardListSkeleton(layout: .section, count: 5)
            case .failed(let error):
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: String(localized: "friends.error.title"),
                    description: error.userMessage,
                    actionTitle: String(localized: "common.retry"),
                    action: { Task { await app.friends.refresh(force: true) } },
                    style: .error
                )
            case .idle:
                if app.friends.lastRefreshedAt == nil {
                    CardListSkeleton(layout: .section, count: 5)
                } else {
                    EmptyState(
                        icon: "person.2",
                        title: String(localized: "friends.empty.title"),
                        description: String(localized: "friends.empty.message")
                    )
                }
            }
        } else {
            let mine = Dictionary(games.map { ($0.id, $0.progress) }, uniquingKeysWith: { first, _ in first })
            CardList(friends, layout: .section, onOpen: { openedFriend = $0.accountId }) { (friend: FriendRecord) in
                PersonRow(
                    name: friend.displayName,
                    subtitle: standingText(friend, mine: mine),
                    avatar: FriendAvatar(friend: friend)
                )
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    private func standingText(_ friend: FriendRecord, mine: [String: Int]) -> String {
        if friend.isHidden { return String(localized: "friends.hidden") }
        let theirs = Dictionary(
            titles.filter { $0.friendId == friend.accountId }.map { ($0.gameId, $0.progress) },
            uniquingKeysWith: { first, _ in first }
        )
        let standing = FriendStanding(FriendComparison.shared(mine: mine, theirs: theirs).values)
        if standing.shared == 0 { return String(localized: "friends.noShared") }
        return String(localized: "friends.standing \(standing.ahead) \(standing.shared)")
    }
}

/// A friend's picture, round, 40 pt across, as `PersonRow` lays it out.
struct FriendAvatar: View {
    let friend: FriendRecord
    var size: CGFloat = AppIconSize.xxl

    var body: some View {
        RemotePhoto(key: "avatar-\(friend.accountId)", url: friend.avatarURL)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}

extension FriendRecord {
    /// The online id, or a stand-in until the profile is read.
    var displayName: String {
        onlineId.isEmpty ? String(localized: "friends.unnamed") : onlineId
    }
}
