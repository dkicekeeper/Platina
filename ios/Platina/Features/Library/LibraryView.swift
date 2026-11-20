import SwiftUI
import DesignTokens
import DesignComponents
import PSNKit

/// Stage 0's main screen: who is signed in and their PS5 games.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var model: LibraryModel
    @State private var selectedGame: TrophyTitle?
    @State private var isConfirmingSignOut = false

    init(app: AppModel) {
        _model = State(initialValue: LibraryModel(client: app.client, onError: { [weak app] error in
            app?.handle(error)
        }))
    }

    var body: some View {
        NavigationStack {
            content
                .background(AppColors.Background.base)
                .navigationTitle(Text("library.title"))
                .navigationDestination(item: $selectedGame) { game in
                    GameView(title: game, app: app)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                isConfirmingSignOut = true
                            } label: {
                                Label(String(localized: "library.signOut"), systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Label(String(localized: "library.account"), systemImage: "person.crop.circle")
                        }
                    }
                }
                .confirmationDialog(
                    Text("library.signOut.confirm"),
                    isPresented: $isConfirmingSignOut,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "library.signOut"), role: .destructive) {
                        Task { await app.signOut() }
                    }
                }
        }
        .task {
            // Once: coming back from a game does not load the library again (pull to refresh does).
            if !model.hasLoaded { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .failed(let message):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: String(localized: "library.error.title"),
                description: message,
                actionTitle: String(localized: "common.retry"),
                action: { Task { await model.load() } },
                style: .error
            )
            .screenPadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading, .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    SkeletonReveal(isLoading: model.state == .loading) {
                        ProfileCard(profile: model.profile, summary: model.summary, platinums: model.platinumCount, games: model.games.count)
                    } skeleton: {
                        StatsStripSkeleton(count: 4)
                    }

                    SectionHeader(String(localized: "library.games.header"), style: .large)

                    SkeletonReveal(isLoading: model.state == .loading) {
                        if model.games.isEmpty {
                            EmptyState(
                                icon: "gamecontroller",
                                title: String(localized: "library.empty.title"),
                                description: String(localized: "library.empty.message")
                            )
                        } else {
                            CardList(model.games, layout: .cards, onOpen: { selectedGame = $0 }) { game in
                                GameRow(game: game)
                            }
                        }
                    } skeleton: {
                        VStack(spacing: AppSpacing.md) {
                            ForEach(0..<5, id: \.self) { _ in
                                ThumbnailRowSkeleton()
                                    .padding(AppSpacing.lg)
                                    .cardStyle()
                            }
                        }
                    }
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.xxl)
            }
            .refreshable { await model.load() }
        }
    }
}

/// The person's level, avatar and totals.
private struct ProfileCard: View {
    let profile: PSNProfile?
    let summary: TrophySummary?
    let platinums: Int
    let games: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let profile {
                HStack(spacing: AppSpacing.md) {
                    RemotePhoto(key: "avatar-\(profile.onlineId)", url: profile.avatarURL)
                        .frame(width: AppIconSize.Tile.md, height: AppIconSize.Tile.md)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(verbatim: profile.onlineId)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.Text.primary)
                        if let summary {
                            Text("library.level \(summary.level) \(summary.progress)")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.Text.secondary)
                        }
                    }
                }
            }
            StatsStrip(items: [
                .init(value: summary.map { "\($0.level)" } ?? "–", title: String(localized: "library.stat.level")),
                .init(value: "\(platinums)", title: String(localized: "library.stat.platinums")),
                .init(value: summary.map { "\($0.earnedTrophies.total)" } ?? "–", title: String(localized: "library.stat.trophies")),
                .init(value: "\(games)", title: String(localized: "library.stat.games")),
            ])
        }
    }
}

/// A game in the library: its icon, name, progress and how many of each trophy.
struct GameRow: View {
    let game: TrophyTitle

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            ThumbnailRow(title: game.trophyTitleName) {
                RemotePhoto(key: "game-\(game.id)", url: game.iconURL)
            } details: {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    TrophyCountsLine(earned: game.earnedTrophies, defined: game.definedTrophies)
                    RelativeTime(game.lastUpdatedDateTime)
                }
            }
            ProgressRing(
                progress: Double(game.progress) / 100,
                size: AppIconSize.Tile.sm,
                lineWidth: 4,
                overrideColor: game.isPlatinumEarned ? TrophyType.platinum.color : nil,
                accessibilityLabel: String(localized: "game.progress \(game.progress)"),
                showsTrack: true
            )
            .overlay {
                Text(verbatim: "\(game.progress)%")
                    .font(AppTypography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.Text.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// "🏆 1 · 12/21 · 2/4 · 22/31": what is earned of each trophy type, platinum first.
struct TrophyCountsLine: View {
    let earned: TrophyCounts
    let defined: TrophyCounts

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(TrophyType.allCases.filter { defined[$0] > 0 }, id: \.self) { type in
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(type.color)
                    Text(verbatim: "\(earned[type])/\(defined[type])")
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("trophy.counts.accessibility \(type.title) \(earned[type]) \(defined[type])"))
            }
        }
        .lineLimit(1)
    }
}
