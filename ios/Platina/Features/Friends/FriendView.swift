import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// One friend against the person: how many shared games each is ahead in, then the shared
/// games, the widest gap first, both progresses side by side.
struct FriendView: View {
    let accountId: String

    @Query private var friends: [FriendRecord]
    @Query private var titles: [FriendTitleRecord]
    @Query private var games: [GameRecord]
    @State private var openedGame: String?

    init(accountId: String) {
        self.accountId = accountId
        let id = accountId
        _friends = Query(filter: #Predicate<FriendRecord> { $0.accountId == id })
        _titles = Query(filter: #Predicate<FriendTitleRecord> { $0.friendId == id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                if let friend = friends.first {
                    content(friend)
                } else {
                    PersonRowSkeleton(style: .card)
                    CardListSkeleton(layout: .section, count: 5)
                }
            }
            .screenPadding()
            .readableWidth()
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.Background.page)
        .navigationTitle(Text(verbatim: friends.first?.displayName ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedGame) { gameId in
            GameView(gameId: gameId)
        }
    }

    @ViewBuilder
    private func content(_ friend: FriendRecord) -> some View {
        let shared = sharedGames
        let standing = FriendStanding(shared.map(\.comparison))
        PersonRow(
            name: friend.displayName,
            subtitle: friend.isHidden
                ? String(localized: "friends.hidden")
                : (standing.shared == 0 ? String(localized: "friends.noShared") : String(localized: "friends.standing \(standing.ahead) \(standing.shared)")),
            avatar: FriendAvatar(friend: friend, size: AppIconSize.Tile.xl),
            style: .card
        )
        if friend.isHidden {
            EmptyState(
                icon: "eye.slash",
                title: String(localized: "friends.hidden"),
                description: String(localized: "friend.hidden.message \(friend.displayName)")
            )
        } else if shared.isEmpty {
            EmptyState(icon: "gamecontroller", title: String(localized: "friends.noShared"))
        } else {
            StatsStrip(items: [
                .init(value: standing.ahead.formatted(), title: String(localized: "friend.stat.ahead")),
                .init(value: standing.behind.formatted(), title: String(localized: "friend.stat.behind")),
                .init(value: standing.tied.formatted(), title: String(localized: "friend.stat.tied")),
            ])
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "friend.games.header"), systemImage: "gamecontroller")
                CardList(shared, layout: .section, onOpen: { openedGame = $0.game.id }) { (entry: SharedGame) in
                    SharedGameRow(entry: entry, friendName: friend.displayName)
                }
            }
        }
    }

    /// The games both have, the widest gap first.
    private var sharedGames: [SharedGame] {
        let theirs = Dictionary(titles.map { ($0.gameId, $0.progress) }, uniquingKeysWith: { first, _ in first })
        return games.compactMap { game -> SharedGame? in
            guard let other = theirs[game.id] else { return nil }
            return SharedGame(game: game, comparison: FriendComparison(mine: game.progress, theirs: other))
        }
        .sorted {
            $0.comparison.gap != $1.comparison.gap
                ? $0.comparison.gap > $1.comparison.gap
                : $0.game.name.localizedStandardCompare($1.game.name) == .orderedAscending
        }
    }
}

/// A game both the person and a friend have, compared.
struct SharedGame: Identifiable {
    let game: GameRecord
    let comparison: FriendComparison
    var id: String { game.id }
}

/// A shared game: its icon and name, then the person's and the friend's progress, the leader's
/// bar in the accent (platinum-coloured once they have the platinum).
private struct SharedGameRow: View {
    let entry: SharedGame
    let friendName: String

    var body: some View {
        ThumbnailRow(title: entry.game.name) {
            RemotePhoto(key: "game-\(entry.game.id)", url: entry.game.iconURL)
        } details: {
            Grid(alignment: .leading, horizontalSpacing: AppSpacing.sm, verticalSpacing: AppSpacing.xs) {
                bar(String(localized: "friend.you"), value: entry.comparison.mine, leads: entry.comparison.leader == .me)
                bar(friendName, value: entry.comparison.theirs, leads: entry.comparison.leader == .friend)
            }
        }
        .padding(.vertical, AppSpacing.md)
        .rowDividerInset(64 + AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func bar(_ name: String, value: Int, leads: Bool) -> some View {
        GridRow {
            Text(verbatim: name)
                .font(AppTypography.caption)
                .foregroundStyle(leads ? AppColors.Text.primary : AppColors.Text.secondary)
                .lineLimit(1)
            LinearProgressBar(value: Double(value) / 100, color: leads ? AppColors.accent : AppColors.Text.tertiary, height: 6)
            Text(verbatim: "\(value)%")
                .font(AppTypography.caption)
                .monospacedDigit()
                .foregroundStyle(leads ? AppColors.Text.primary : AppColors.Text.secondary)
                .gridColumnAlignment(.trailing)
        }
    }
}
