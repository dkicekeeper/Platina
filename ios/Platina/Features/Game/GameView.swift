import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

enum TrophyFilter: String, CaseIterable, Hashable {
    case all, notEarned, earned

    var title: String {
        switch self {
        case .all: String(localized: "game.filter.all")
        case .notEarned: String(localized: "game.filter.notEarned")
        case .earned: String(localized: "game.filter.earned")
        }
    }
}

enum TrophySort: String, CaseIterable, Hashable {
    /// Platinum first, then gold, silver, bronze; the most common first within a type.
    case type
    /// The rarest first.
    case rarity
    /// The latest earned first; the rest after them.
    case earned

    var title: String {
        switch self {
        case .type: String(localized: "trophySort.type")
        case .rarity: String(localized: "trophySort.rarity")
        case .earned: String(localized: "trophySort.earned")
        }
    }
}

/// A game: its progress, time played, the person's plan and every trophy (docs/PLAN.md §3.3).
/// The guide and the road map come with Plati (stage 3).
struct GameView: View {
    let gameId: String

    @Environment(AppModel.self) private var app
    @Query private var games: [GameRecord]
    @Query private var plans: [GamePlanRecord]
    @Query private var sessions: [PlaySessionRecord]
    @State private var filter: TrophyFilter = .notEarned
    @State private var sort: TrophySort = .type
    @State private var revealedHidden: Set<Int> = []
    /// The trophies PlayStation's Game Help covers: a mark in the list.
    @State private var helpedTrophies: Set<Int> = []
    @State private var openedTrophy: String?
    @State private var isLoadingTrophies = false
    @State private var isShowingChat = false
    @State private var isShowingShare = false

    init(gameId: String) {
        self.gameId = gameId
        let id = gameId
        _games = Query(filter: #Predicate<GameRecord> { $0.id == id })
        _plans = Query(filter: #Predicate<GamePlanRecord> { $0.gameId == id })
        _sessions = Query(
            filter: #Predicate<PlaySessionRecord> { $0.gameId == id && $0.endedAt != nil },
            sort: \PlaySessionRecord.startedAt,
            order: .reverse
        )
    }

    private var status: GamePlanStatus { plans.first?.status ?? .none }

    var body: some View {
        Group {
            if let game = games.first {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        GameHeader(
                            game: game,
                            status: status,
                            isSessionRunning: app.sessions.current?.gameId == gameId,
                            onPlan: { newStatus in _ = try? app.store.setPlan(newStatus, for: gameId) },
                            onSession: {
                                if app.sessions.current?.gameId == gameId {
                                    app.isShowingSession = true
                                } else {
                                    Task { await app.startSession(gameId: gameId) }
                                }
                            }
                        )
                        WalkthroughSection(game: game)
                        GuideSection(game: game)
                        SegmentedPicker(
                            title: String(localized: "game.filter.title"),
                            selection: $filter,
                            options: TrophyFilter.allCases.map { (label: $0.title, value: $0) }
                        )
                        trophies(of: game)
                        if !sessions.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SectionHeader(String(localized: "game.sessions.header"), systemImage: "list.bullet.rectangle")
                                CardList(Array(sessions.prefix(10)), layout: .section, onOpen: { app.endedSession = $0 }) { (session: PlaySessionRecord) in
                                    SessionRow(session: session)
                                }
                            }
                        }
                    }
                    .screenPadding()
                    .readableWidth()
                    .padding(.bottom, AppSpacing.xxl)
                }
                .navigationTitle(Text(verbatim: game.name))
                .sheet(isPresented: $isShowingChat) {
                    GameChatSheet(gameId: game.id, gameName: game.name)
                }
                .sheet(isPresented: $isShowingShare) {
                    GameShareSheet(game: game)
                }
            } else {
                EmptyState(icon: "questionmark.square.dashed", title: String(localized: "game.missing"))
                    .screenPadding()
            }
        }
        .background(AppColors.Background.base)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingChat = true
                } label: {
                    Label(String(localized: "game.askPlati"), systemImage: "bubble.left.and.text.bubble.right")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $sort) {
                        ForEach(TrophySort.allCases, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    } label: {
                        Text("library.sort")
                    }
                    Divider()
                    Button {
                        isShowingShare = true
                    } label: {
                        Label(String(localized: "game.share"), systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label(String(localized: "game.more"), systemImage: "ellipsis")
                }
            }
        }
        .navigationDestination(item: $openedTrophy) { key in
            TrophyView(trophyKey: key)
        }
        .refreshable {
            await app.sync.sync(force: true, priority: gameId)
        }
        .task {
            isLoadingTrophies = true
            await app.sync.refreshGame(gameId)
            isLoadingTrophies = false
        }
        .task(id: gameId) {
            helpedTrophies = await app.gameHelp.helpedTrophyIds(gameId: gameId)
        }
    }

    @ViewBuilder
    private func trophies(of game: GameRecord) -> some View {
        if game.trophies.isEmpty {
            if isLoadingTrophies || game.detailsLastUpdated == nil {
                CardListSkeleton(layout: .section, count: 6)
            } else {
                EmptyState(icon: "trophy", title: String(localized: "game.empty.noneEarned"))
            }
        } else {
            let sections = sections(of: game)
            if sections.isEmpty {
                if filter == .notEarned {
                    EmptyState(icon: "checkmark.seal", title: String(localized: "game.empty.allEarned"))
                } else {
                    EmptyState(icon: "trophy", title: String(localized: "game.empty.noneEarned"))
                }
            } else {
                ForEach(sections) { section in
                    TrophySectionView(
                        section: section,
                        showsHeader: game.groups.count > 1,
                        revealedHidden: $revealedHidden,
                        helpedTrophies: helpedTrophies,
                        onOpen: { openedTrophy = $0 }
                    )
                }
            }
        }
    }

    private func sections(of game: GameRecord) -> [TrophySection] {
        let visible = game.trophies.filter { trophy in
            switch filter {
            case .all: true
            case .notEarned: !trophy.isEarned
            case .earned: trophy.isEarned
            }
        }
        let byGroup = Dictionary(grouping: visible, by: \.groupId)
        // The base game ("default") first, then the DLC in their order ("001", "002"…).
        let groupIds = game.groups.isEmpty ? Array(byGroup.keys) : game.groups.map(\.groupId)
        let groupOrder = groupIds.sorted { lhs, rhs in
            if (lhs == "default") != (rhs == "default") { return lhs == "default" }
            return lhs < rhs
        }
        return groupOrder.compactMap { id in
            guard let items = byGroup[id], !items.isEmpty else { return nil }
            let group = game.groups.first { $0.groupId == id }
            return TrophySection(id: id, title: sectionTitle(group), trophies: items.sorted(by: sort.areInIncreasingOrder))
        }
    }

    private func sectionTitle(_ group: TrophyGroupRecord?) -> String? {
        guard let group else { return nil }
        return group.isBaseGame ? String(localized: "game.group.base") : group.name
    }
}

extension TrophySort {
    func areInIncreasingOrder(_ lhs: TrophyRecord, _ rhs: TrophyRecord) -> Bool {
        switch self {
        case .type:
            if lhs.type != rhs.type { return lhs.type < rhs.type }
            return (lhs.earnedRate ?? 100) > (rhs.earnedRate ?? 100)
        case .rarity:
            return (lhs.earnedRate ?? 100) < (rhs.earnedRate ?? 100)
        case .earned:
            switch (lhs.earnedAt, rhs.earnedAt) {
            case let (left?, right?): return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.trophyId < rhs.trophyId
            }
        }
    }
}

/// The trophies of one group (the base game or a DLC) under the current filter.
struct TrophySection: Identifiable {
    let id: String
    let title: String?
    let trophies: [TrophyRecord]
}

/// The game's cover, progress, counts, time played and the person's plan.
private struct GameHeader: View {
    let game: GameRecord
    let status: GamePlanStatus
    let isSessionRunning: Bool
    let onPlan: (GamePlanStatus) -> Void
    let onSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .center, spacing: AppSpacing.lg) {
                RemotePhoto(key: "game-\(game.id)", url: game.iconURL)
                    .frame(width: 96, height: 96)
                    .clipShape(.rect(cornerRadius: AppRadius.lg))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(verbatim: "\(game.progress)%")
                        .font(AppTypography.h2)
                        .monospacedDigit()
                        .foregroundStyle(game.isPlatinumEarned ? TrophyType.platinum.color : AppColors.Text.primary)
                    LinearProgressBar(
                        value: Double(game.progress) / 100,
                        color: game.isPlatinumEarned ? TrophyType.platinum.color : AppColors.accent
                    )
                    TrophyCountsLine(earned: game.earned, defined: game.defined)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            if let seconds = game.playSeconds, seconds > 0 {
                StatsStrip(items: playItems(seconds: seconds))
            }

            DSButton(
                isSessionRunning ? String(localized: "game.session.open") : String(localized: "game.session.start"),
                systemImage: isSessionRunning ? "record.circle" : "play.fill",
                fullWidth: true,
                action: onSession
            )

            UniversalFilterButton(
                title: status.title,
                isSelected: status != .none,
                icon: { Icon(status.systemImage, size: AppIconSize.sm) },
                menuContent: {
                    ForEach(GamePlanStatus.allCases, id: \.self) { option in
                        Button {
                            onPlan(option)
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                }
            )
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func playItems(seconds: TimeInterval) -> [StatsStrip.Item] {
        var items: [StatsStrip.Item] = [
            .init(value: PlayTimeText.duration(seconds), title: String(localized: "game.played")),
        ]
        if let lastPlayed = game.lastPlayed {
            items.append(.init(value: Formatting.relativeTime(lastPlayed), title: String(localized: "game.lastPlayed")))
        }
        if let count = game.playCount, count > 0 {
            items.append(.init(value: count.formatted(), title: String(localized: "game.launches")))
        }
        return items
    }
}

/// One group's trophies in one glass card, under the group's name when the game has DLC.
private struct TrophySectionView: View {
    let section: TrophySection
    let showsHeader: Bool
    @Binding var revealedHidden: Set<Int>
    var helpedTrophies: Set<Int> = []
    let onOpen: (String) -> Void
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if showsHeader, let title = section.title {
                SectionHeader(title)
            }
            CardList(section.trophies, layout: .section) { (trophy: TrophyRecord) in
                TrophyRow(
                    trophy: trophy,
                    isRevealed: showsHiddenTrophies || revealedHidden.contains(trophy.trophyId),
                    hasGameHelp: helpedTrophies.contains(trophy.trophyId)
                )
                    .contentShape(Rectangle())
                    .onTapGesture { tap(trophy) }
            }
        }
    }

    private func tap(_ trophy: TrophyRecord) {
        if trophy.isHidden, !trophy.isEarned, !showsHiddenTrophies, !revealedHidden.contains(trophy.trophyId) {
            revealedHidden.insert(trophy.trophyId)
        } else {
            onOpen(trophy.key)
        }
    }
}

/// One trophy: its icon (grey until earned), name, description, rarity and progress. A hidden
/// trophy not earned yet keeps its name and description under a tap, so nothing is spoiled.
struct TrophyRow: View {
    let trophy: TrophyRecord
    var isRevealed = false
    /// PlayStation's Game Help covers this trophy (shown once it is not a spoiler).
    var hasGameHelp = false

    private var isSpoilerHidden: Bool { trophy.isHidden && !trophy.isEarned && !isRevealed }

    var body: some View {
        ThumbnailRow(title: isSpoilerHidden ? String(localized: "trophy.hidden.title") : trophy.name) {
            if isSpoilerHidden {
                AchievementMedal(systemImage: "questionmark", color: trophy.type.color, isEarned: false, size: 64)
            } else {
                RemotePhoto(key: "trophy-\(trophy.key)", url: trophy.iconURL)
                    .saturation(trophy.isEarned ? 1 : 0)
                    .opacity(trophy.isEarned ? 1 : 0.7)
            }
        } details: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if isSpoilerHidden {
                    Text("trophy.hidden.reveal")
                        .foregroundStyle(AppColors.accent)
                } else if !trophy.detail.isEmpty {
                    Text(verbatim: trophy.detail)
                        .foregroundStyle(AppColors.Text.secondary)
                        .lineLimit(3)
                }
                if let progress = trophy.progress, !trophy.isEarned {
                    HStack(spacing: AppSpacing.sm) {
                        LinearProgressBar(value: progress.fraction, color: trophy.type.color, height: 6)
                        Text(verbatim: "\(progress.current)/\(progress.target)")
                            .monospacedDigit()
                    }
                }
                MetaLine(TrophyMeta.items(for: trophy) + (hasGameHelp && !isSpoilerHidden ? [TrophyMeta.gameHelp] : []))
            }
        }
        .padding(.vertical, AppSpacing.md)
        .rowDividerInset(64 + AppSpacing.md)
    }
}

enum TrophyMeta {
    static func items(for trophy: TrophyRecord) -> [MetaItem] {
        var items: [MetaItem] = [.label(trophy.type.title, systemImage: trophy.type.systemImage, tint: trophy.type.color)]
        if let rate = trophy.earnedRate {
            items.append(.text(rateText(rate)))
        }
        if let earnedAt = trophy.earnedAt {
            items.append(.label(earnedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.circle.fill", tint: AppColors.success))
        }
        return items
    }

    /// The trophy has PlayStation's Game Help.
    static var gameHelp: MetaItem {
        .label(String(localized: "trophy.gameHelp.badge"), systemImage: "questionmark.bubble", tint: AppColors.accent)
    }

    static func rateText(_ rate: Double) -> String {
        String(localized: "trophy.rate \(rate.formatted(.number.precision(.fractionLength(1))))")
    }
}
