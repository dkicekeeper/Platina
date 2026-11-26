import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// The person and their numbers (docs/PLAN.md §3.7): level, platinums, months, activity, the
/// platinum shelf, the rarest trophies. Friends are behind the people button; the account and the
/// rest are in Settings (the gear).
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Query private var profiles: [ProfileRecord]
    @Query private var games: [GameRecord]
    @Query private var plans: [GamePlanRecord]
    @Query(filter: #Predicate<TrophyRecord> { $0.isEarned == true }) private var earnedRecords: [TrophyRecord]
    @State private var openedGame: String?

    private var computedStats: LibraryStats {
        let statuses = Dictionary(plans.map { ($0.gameId, $0.status) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(games.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let earned = earnedRecords.compactMap { record -> EarnedTrophy? in
            guard let earnedAt = record.earnedAt else { return nil }
            return EarnedTrophy(
                gameId: record.gameId, gameName: names[record.gameId] ?? "", trophyId: record.trophyId,
                name: record.name, type: record.type, earnedAt: earnedAt, earnedRate: record.earnedRate,
                iconURL: record.iconURL
            )
        }
        return StatsCalculator.compute(
            games: games.map { $0.summary(status: statuses[$0.id] ?? .none) },
            trophies: earned
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    SyncStatusBanner()
                    if let profile = profiles.first {
                        let stats = computedStats
                        ProfileHeader(profile: profile)
                        StatsStrip(items: [
                            .init(value: stats.platinumCount.formatted(), title: String(localized: "profile.stat.platinums")),
                            .init(value: stats.completedCount.formatted(), title: String(localized: "profile.stat.completed")),
                            .init(value: stats.earned.total.formatted(), title: String(localized: "profile.stat.trophies")),
                            .init(value: PlayTimeText.hours(stats.totalPlayTime), title: String(localized: "profile.stat.hours")),
                        ])
                        StatsStrip(items: TrophyType.allCases.map { type in
                            .init(value: stats.earned[type].formatted(), title: type.title)
                        })
                        StreakCard(
                            systemImage: "flame.fill",
                            isActive: stats.currentStreak > 0,
                            title: String(localized: "profile.streak.title"),
                            subtitle: String(localized: "profile.streak.best \(stats.bestStreak)"),
                            value: stats.currentStreak.formatted(),
                            valueCaption: String(localized: "profile.streak.days")
                        )
                        // Two in a row where they fit (an iPad, a Mac window), one on a phone.
                        LazyVGrid(columns: sectionColumns, alignment: .leading, spacing: AppSpacing.xl) {
                            monthsSection(stats)
                            activitySection(stats)
                            platinumShelf(stats)
                            rarestSection(stats)
                        }
                    } else {
                        StatsStripSkeleton(count: 4)
                        StatsStripSkeleton(count: 4)
                        StreakCardSkeleton()
                    }
                }
                .screenPadding()
                .readableWidth(AppLayout.wideWidth)
                .padding(.bottom, AppSpacing.xxl)
            }
            .background(AppColors.Background.page)
            .navigationTitle(Text("profile.title"))
            .dsRefreshable { await app.sync.sync(force: true) }
            .navigationDestination(item: $openedGame) { gameId in
                GameView(gameId: gameId)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FriendsView()
                    } label: {
                        Label(String(localized: "friends.title"), systemImage: "person.2")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label(String(localized: "settings.title"), systemImage: "gearshape")
                    }
                }
            }
        }
    }

    // MARK: Sections

    /// The sections' columns: half a readable column at least, so a phone holds one and the wide
    /// column of an iPad or a Mac window two (a chart and its neighbour keep a phone's width).
    private var sectionColumns: [GridItem] { AppLayout.cardColumns(minimum: AppLayout.readableWidth / 2) }

    @ViewBuilder
    private func monthsSection(_ stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "profile.months.header"))
            BarChart(
                dataPoints: stats.months.map(MonthPoint.point),
                series: .keyed("trophies", name: String(localized: "profile.months.series"), coloring: .solid(AppColors.accent)),
                valueFormat: .custom { Int($0).formatted() }
            )
            .padding(AppSpacing.lg)
            .cardStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func activitySection(_ stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "profile.activity.header"))
            CalendarHeatmap(values: stats.days, weeks: 26, color: AppColors.accent, valueFormat: .custom { Int($0).formatted() })
                .padding(AppSpacing.lg)
                .cardStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func platinumShelf(_ stats: LibraryStats) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "profile.platinums.header"), systemImage: "trophy.fill", tint: TrophyType.platinum.color)
            if stats.platinums.isEmpty {
                EmptyState(
                    icon: "trophy",
                    title: String(localized: "profile.platinums.empty.title"),
                    description: String(localized: "profile.platinums.empty.message"),
                    style: .compact
                )
            } else {
                CardList(stats.platinums, layout: .section, onOpen: { openedGame = $0.gameId }) { (trophy: EarnedTrophy) in
                    EarnedTrophyRow(trophy: trophy, title: trophy.gameName, detail: trophy.earnedAt.formatted(date: .long, time: .omitted))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rarestSection(_ stats: LibraryStats) -> some View {
        if !stats.rarest.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // The rows show each trophy's share of players; the header says once what it is.
                SectionHeader(String(localized: "profile.rarest.header"), systemImage: "sparkles")
                    .infoTip(TrophyMeta.rateInfoMessage, title: TrophyMeta.rateInfoTitle)
                CardList(stats.rarest, layout: .section, onOpen: { openedGame = $0.gameId }) { (trophy: EarnedTrophy) in
                    EarnedTrophyRow(
                        trophy: trophy,
                        title: trophy.name,
                        detail: "\(trophy.gameName) · \(TrophyMeta.rateText(trophy.earnedRate ?? 0))"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The avatar, the online id and the level with its progress.
private struct ProfileHeader: View {
    let profile: ProfileRecord

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            RemotePhoto(key: "avatar-\(profile.accountId)", url: profile.avatarURL)
                .frame(width: AppIconSize.Tile.xl, height: AppIconSize.Tile.xl)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(verbatim: profile.onlineId ?? "")
                    .font(AppTypography.h4)
                    .foregroundStyle(AppColors.Text.primary)
                Text("profile.level \(profile.level) \(profile.levelProgress)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
                LinearProgressBar(value: Double(profile.levelProgress) / 100, color: AppColors.accent, height: 6)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// An earned trophy in a list: its icon, a title and a line under it.
private struct EarnedTrophyRow: View {
    let trophy: EarnedTrophy
    let title: String
    let detail: String

    var body: some View {
        ThumbnailRow(title: title) {
            RemotePhoto(key: "trophy-\(trophy.id)", url: trophy.iconURL)
        } details: {
            Text(verbatim: detail)
                .lineLimit(2)
        }
        .padding(.vertical, AppSpacing.md)
        .rowDividerInset(64 + AppSpacing.md)
    }
}

/// A month of trophies as a bar of the chart.
private enum MonthPoint {
    static func point(_ month: MonthCount) -> ChartValuePoint {
        ChartValuePoint(
            label: month.month.formatted(.iso8601.year().month()),
            axisLabel: month.month.formatted(.dateTime.month(.abbreviated)),
            title: month.month.formatted(.dateTime.month(.wide).year()),
            date: month.month,
            isPartial: month.isCurrent,
            values: ["trophies": Double(month.count)]
        )
    }
}
