import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// "The path" (docs/PLAN.md §3.1): what is running on the console, the session, the games the
/// person goes for, the trophies almost earned, the latest trophies and sessions.
struct PathView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \GameRecord.lastUpdated, order: .reverse) private var games: [GameRecord]
    @Query private var plans: [GamePlanRecord]
    @Query(Self.recentTrophies) private var recentTrophies: [TrophyRecord]
    @Query(Self.recentSessions) private var recentSessions: [PlaySessionRecord]
    @State private var runningGameId: String?
    @State private var openedGame: String?

    private static var recentTrophies: FetchDescriptor<TrophyRecord> {
        var descriptor = FetchDescriptor<TrophyRecord>(
            predicate: #Predicate { $0.isEarned == true },
            sortBy: [SortDescriptor(\.earnedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 8
        return descriptor
    }

    private static var recentSessions: FetchDescriptor<PlaySessionRecord> {
        var descriptor = FetchDescriptor<PlaySessionRecord>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private var chasing: [GameRecord] {
        let ids = Set(plans.filter { $0.status == .chasing }.map(\.gameId))
        return games.filter { ids.contains($0.id) && !$0.isCompleted }
    }

    private var closeToPlatinum: [GameRecord] {
        let shelved = Set(plans.filter { $0.status.isShelved }.map(\.gameId))
        let chasingIds = Set(chasing.map(\.id))
        return games
            .filter { $0.definedPlatinum > 0 && !$0.isPlatinumEarned && $0.progress >= 60 }
            .filter { !shelved.contains($0.id) && !chasingIds.contains($0.id) }
            .sorted { $0.progress > $1.progress }
            .prefix(3)
            .map { $0 }
    }

    /// Unearned trophies with a counter at least half full, the fullest first.
    private var almostEarned: [TrophyRecord] {
        games
            .flatMap(\.trophies)
            .filter { !$0.isEarned && ($0.progress?.fraction ?? 0) >= 0.5 }
            .sorted { ($0.progress?.fraction ?? 0) > ($1.progress?.fraction ?? 0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    SyncStatusBanner()
                    runningGameNotice
                    currentSession
                    chasingSection
                    almostSection
                    recentSection
                    sessionsSection
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.xxl)
            }
            .background(AppColors.Background.base)
            .navigationTitle(Text("path.title"))
            .refreshable {
                await app.sync.sync(force: true)
                runningGameId = await app.sync.runningGame(force: true)
            }
            .navigationDestination(item: $openedGame) { gameId in
                GameView(gameId: gameId)
            }
            .task {
                runningGameId = await app.sync.runningGame()
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var runningGameNotice: some View {
        if let runningGameId, app.sessions.current?.gameId != runningGameId,
           let game = games.first(where: { $0.id == runningGameId }) {
            NoticeCard(
                title: String(localized: "path.running.title \(game.name)"),
                message: String(localized: "path.running.message"),
                actionTitle: String(localized: "path.running.start"),
                actionSystemImage: "play.fill",
                action: { Task { await app.startSession(gameId: game.id) } },
                onHide: { self.runningGameId = nil }
            ) {
                RemotePhoto(key: "game-\(game.id)", url: game.iconURL)
                    .frame(width: NoticeCardMetrics.leadingSize, height: NoticeCardMetrics.leadingSize)
                    .clipShape(.rect(cornerRadius: AppRadius.md))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var currentSession: some View {
        if let session = app.sessions.current {
            Button {
                app.isShowingSession = true
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Icon("record.circle", size: AppIconSize.lg, tint: .monochrome(AppColors.destructive))
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("path.session.title")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.Text.secondary)
                        Text(verbatim: session.gameName)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(AppColors.Text.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    RelativeTime(session.clockStart, style: .clock)
                        .font(AppTypography.numbers(AppTypography.h4))
                        .foregroundStyle(AppColors.Text.primary)
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var chasingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "path.chasing.header"), systemImage: "scope")
            if chasing.isEmpty {
                if closeToPlatinum.isEmpty {
                    EmptyState(
                        icon: "scope",
                        title: String(localized: "path.chasing.empty.title"),
                        description: String(localized: "path.chasing.empty.message"),
                        style: .compact
                    )
                }
            } else {
                CardList(chasing, layout: .cards, onOpen: { openedGame = $0.id }) { (game: GameRecord) in
                    ChasingGameCard(game: game)
                }
            }
            if !closeToPlatinum.isEmpty {
                SectionHeader(String(localized: "path.close.header"), systemImage: "flag.checkered")
                CardList(closeToPlatinum, layout: .cards, onOpen: { openedGame = $0.id }) { (game: GameRecord) in
                    ChasingGameCard(game: game)
                }
            }
        }
    }

    @ViewBuilder
    private var almostSection: some View {
        let trophies = almostEarned
        if !trophies.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "path.almost.header"), systemImage: "gauge.with.dots.needle.67percent")
                VStack(spacing: AppSpacing.lg) {
                    ForEach(trophies, id: \.key) { trophy in
                        Button {
                            openedGame = trophy.gameId
                        } label: {
                            AchievementProgressRow(
                                label: trophy.game?.name ?? "",
                                title: trophy.name,
                                progressText: "\(trophy.progress?.current ?? 0)/\(trophy.progress?.target ?? 0)",
                                fraction: trophy.progress?.fraction ?? 0,
                                systemImage: trophy.type.systemImage,
                                color: trophy.type.color
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !recentTrophies.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "path.recent.header"), systemImage: "clock.arrow.circlepath")
                ActivityTimeline(recentTrophies) { trophy in
                    TimelineMarker(systemImage: trophy.type.systemImage, color: trophy.type.color)
                } content: { trophy in
                    Button {
                        openedGame = trophy.gameId
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: trophy.name)
                                .font(AppTypography.bodyEmphasis)
                                .foregroundStyle(AppColors.Text.primary)
                            MetaLine([
                                .text(trophy.game?.name ?? ""),
                                .text(trophy.earnedAt.map { Formatting.relativeTime($0) } ?? ""),
                            ])
                            .font(AppTypography.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        if !recentSessions.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "path.sessions.header"), systemImage: "list.bullet.rectangle")
                CardList(recentSessions, layout: .section, onOpen: { openedGame = $0.gameId }) { (session: PlaySessionRecord) in
                    SessionRow(session: session)
                }
            }
        }
    }
}

/// A game the person goes for: its progress and what is left, with a button to play.
private struct ChasingGameCard: View {
    @Environment(AppModel.self) private var app
    let game: GameRecord

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            GameRow(game: game, status: .none)
            HStack {
                Text("path.left \(game.defined.total - game.earned.total)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
                Spacer()
                DSButton(String(localized: "path.play"), systemImage: "play.fill", size: .small) {
                    Task { await app.startSession(gameId: game.id) }
                }
            }
        }
    }
}

/// A finished session in a list: the game, the day, the time and the trophies it brought.
struct SessionRow: View {
    let session: PlaySessionRecord

    var body: some View {
        ItemRow(
            session.gameName,
            detail: session.summary,
            meta: [
                .text(session.startedAt.formatted(date: .abbreviated, time: .shortened)),
                .label(PlayTimeText.duration(session.elapsed(at: session.endedAt ?? Date())), systemImage: "clock"),
                .label(session.earnedTrophyIds.count.formatted(), systemImage: "trophy.fill"),
            ],
            leading: .symbol("gamecontroller.fill"),
            titleLineLimit: 1
        )
    }
}
