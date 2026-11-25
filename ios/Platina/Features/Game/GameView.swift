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

/// The parts of a game's screen under its header, picked by the chips.
enum GameSection: String, CaseIterable, Hashable {
    case trophies, guide, walkthrough, sessions

    var title: String {
        switch self {
        case .trophies: String(localized: "game.section.trophies")
        case .guide: String(localized: "game.section.guide")
        case .walkthrough: String(localized: "game.section.walkthrough")
        case .sessions: String(localized: "game.section.sessions")
        }
    }

    var systemImage: String {
        switch self {
        case .trophies: "trophy"
        case .guide: "map"
        case .walkthrough: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .sessions: "clock.arrow.circlepath"
        }
    }
}

/// A game (docs/PLAN.md §3.3): its header on the game's cover (progress, trophy counts, time
/// played, the session button and the person's plan), then chips for its parts: the trophies,
/// the guide, the walkthrough and the sessions.
struct GameView: View {
    let gameId: String

    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
    @State private var section: GameSection = ScreenshotDemo.screen?.section ?? .trophies
    /// The header shows the game's name; the bar's title stays empty until it scrolls away.
    @State private var isHeroUnderBar = true

    /// The part under the header: on a phone, the chips first.
    private static let sectionsAnchor = "sections"

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
                ScrollViewReader { proxy in
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
                            .gameArt(game)

                            // An iPad or a Mac window: the trophies, and beside them the guide, the
                            // walkthrough and the sessions. Narrower (a phone, a panel open beside
                            // the screen): chips over one part at a time.
                            AdaptiveColumns {
                                trophiesColumn(game)
                            } side: {
                                GuideSection(game: game)
                                WalkthroughSection(game: game)
                                sessionsSection(limit: Self.sideSessions)
                            } narrow: {
                                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                                    ChipPicker(
                                        options: GameSection.allCases,
                                        selection: Binding<GameSection?>(get: { section }, set: { if let new = $0 { section = new } }),
                                        systemImage: { $0.systemImage }
                                    ) { $0.title }
                                    sectionContent(game)
                                }
                            }
                            // Outside the columns' ViewThatFits, which hides ids from scrollTo.
                            .id(Self.sectionsAnchor)
                            .screenPadding()
                            .readableWidth(AppLayout.wideWidth)
                            .padding(.bottom, AppSpacing.xxl)
                        }
                    }
                    .heroScrollEdge(isHeroUnderBar: $isHeroUnderBar)
                    // The App Store's screenshot of the guide: its chips under the bar.
                    .task {
                        guard ScreenshotDemo.screen == .guide, horizontalSizeClass == .compact else { return }
                        try? await Task.sleep(for: .seconds(1.5))
                        proxy.scrollTo(Self.sectionsAnchor, anchor: .top)
                    }
                }
                .navigationTitle(Text(verbatim: isHeroUnderBar ? "" : game.name))
                // A panel beside the game on an iPad or a Mac window, a sheet on a phone.
                .inspector(isPresented: $isShowingChat) {
                    GameChatSheet(gameId: game.id, gameName: game.name) { isShowingChat = false }
                        .inspectorColumnWidth(min: AppLayout.cardMinWidth, ideal: AppLayout.sideColumnWidth)
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
                    // The trophies' order: beside the guide on a wide screen, under their chip
                    // on a phone.
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

    /// How many sessions the side column shows; the chips' Sessions shows them all.
    private static let sideSessions = 5

    /// The part the chips picked.
    @ViewBuilder
    private func sectionContent(_ game: GameRecord) -> some View {
        switch section {
        case .trophies:
            trophiesColumn(game)
        case .guide:
            GuideSection(game: game)
        case .walkthrough:
            WalkthroughSection(game: game)
        case .sessions:
            sessionsSection(limit: nil)
        }
    }

    /// The trophies with their filter: the main column, or the chips' Trophies.
    @ViewBuilder
    private func trophiesColumn(_ game: GameRecord) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            SegmentedPicker(
                title: String(localized: "game.filter.title"),
                selection: $filter,
                options: TrophyFilter.allCases.map { (label: $0.title, value: $0) }
            )
            trophies(of: game)
        }
    }

    /// The game's sessions, the latest first: `limit` of them beside the trophies, all of them
    /// under the chips.
    @ViewBuilder
    private func sessionsSection(limit: Int?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if limit != nil {
                SectionHeader(GameSection.sessions.title, systemImage: GameSection.sessions.systemImage)
            }
            if sessions.isEmpty {
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: String(localized: "game.sessions.empty.title"),
                    description: String(localized: "game.sessions.empty.message"),
                    style: limit == nil ? .standard : .compact
                )
            } else {
                let shown = limit.map { Array(sessions.prefix($0)) } ?? sessions
                CardList(shown, layout: .section, onOpen: { app.endedSession = $0 }) { (session: PlaySessionRecord) in
                    SessionRow(session: session)
                }
            }
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

private extension View {
    /// The game's art behind its header (`.heroBackground(picture:)`). Where the store has the
    /// game hub's cover in two layers, its backdrop with the hero character standing in front of
    /// it, whole under the bars (DesignKit 8.17.0): the cover cropped to a phone's width showed a
    /// shoulder. Else the hub's cover itself (without the title, as the console lays the logo
    /// over it), else the game list's cover, else the trophy list's icon, until the game list has
    /// been read. The game's icon, seen in the list already, stands in blurred until the art has
    /// loaded; the character shows once it is there.
    @ViewBuilder
    func gameArt(_ game: GameRecord) -> some View {
        if let backdrop = game.backdropURL, let character = game.characterURL {
            heroBackground(clearHeight: GameHeader.room) {
                RemotePhoto(key: "game-backdrop-\(game.id)", url: backdrop, placeholderKey: "game-\(game.id)")
            } subject: {
                RemotePhoto(key: "game-character-\(game.id)", url: character)
            }
        } else {
            heroBackground(clearHeight: GameHeader.room) {
                if let art = game.artURL {
                    RemotePhoto(key: "game-art-\(game.id)", url: art, placeholderKey: "game-\(game.id)")
                } else if let cover = game.coverURL {
                    RemotePhoto(key: "game-cover-\(game.id)", url: cover, placeholderKey: "game-\(game.id)")
                } else {
                    RemotePhoto(key: "game-\(game.id)", url: game.iconURL)
                }
            }
        }
    }
}

/// The top of a game's screen, as a film's page in the TV app (`.heroBackground(picture:)`):
/// the game's art from the top of the screen with its title logo (the name where it has none) at
/// the foot of the art's room, then centred on the art's own darkened colours: the trophy counts,
/// the session button and the plan, the progress, and the numbers in a strip of tiles.
private struct GameHeader: View {
    let game: GameRecord
    let status: GamePlanStatus
    let isSessionRunning: Bool
    let onPlan: (GamePlanStatus) -> Void
    let onSession: () -> Void

    /// The art's own room below the bars, sharp with nothing over it but the logo at its foot.
    static let room = AppSpacing.xxxl * 8

    private var progressColor: Color { game.isPlatinumEarned ? TrophyType.platinum.color : AppColors.accent }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            GameTitleLogo(game: game)
                .frame(maxWidth: .infinity, minHeight: Self.room - AppSpacing.lg, alignment: .bottom)

            // White and bold on the art: the first thing read under the title.
            TrophyCountsLine(earned: game.earned, defined: game.defined)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.Text.primary)

            VStack(spacing: AppSpacing.md) {
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

            VStack(spacing: AppSpacing.md) {
                LinearProgressBar(value: Double(game.progress) / 100, color: progressColor)
                StatsStrip(items: stats)
            }
        }
        .screenPadding()
        .readableWidth()
        .padding(.bottom, AppSpacing.xl)
    }

    /// 64% completed · 42 h played · yesterday last played · 37 launches: what PSN knows, in tiles.
    private var stats: [StatsStrip.Item] {
        var items = [StatsStrip.Item(
            value: (Double(game.progress) / 100).formatted(.percent.precision(.fractionLength(0))),
            title: String(localized: "game.stat.progress")
        )]
        if let seconds = game.playSeconds, seconds > 0 {
            items.append(.init(value: PlayTimeText.duration(seconds), title: String(localized: "game.stat.played")))
        }
        if let lastPlayed = game.lastPlayed {
            items.append(.init(value: Formatting.relativeTime(lastPlayed), title: String(localized: "game.stat.lastPlayed")))
        }
        if let count = game.playCount, count > 0 {
            items.append(.init(value: count.formatted(), title: String(localized: "game.stat.launches")))
        }
        return items
    }
}

/// The game's title over its art: the store's logo (a transparent picture) once it has loaded,
/// the name until then and where the game has none, so the hero never shows an empty box.
private struct GameTitleLogo: View {
    let game: GameRecord
    @State private var logo: UIImage?

    private var key: String { "game-logo-\(game.id)" }

    var body: some View {
        Group {
            if let image = logo ?? DesignKitPhotoLoader.cached?(key) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: AppIconSize.Tile.xxxl * 4, maxHeight: AppIconSize.Tile.xxxl * 1.5)
                    .transition(.opacity)
            } else {
                Text(verbatim: game.name)
                    .font(AppTypography.h1)
                    .foregroundStyle(AppColors.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: game.name))
        .accessibilityAddTraits(.isHeader)
        .animation(AppAnimation.gentleSpring, value: logo != nil)
        .task(id: game.logoURL) {
            guard logo == nil, DesignKitPhotoLoader.cached?(key) == nil, let url = game.logoURL else { return }
            logo = await DesignKitPhotoLoader.load(key: key, url: url)
        }
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
        // Text in a colour reads at 4.5:1 on the grey card (DesignKit 8.9.0): the solid metals were
        // 2.1–3.6:1 as text, the system green 2.2:1.
        var items: [MetaItem] = [.label(trophy.type.title, systemImage: trophy.type.systemImage, tint: AppColors.readable(trophy.type.color))]
        if let rate = trophy.earnedRate {
            items.append(.text(rateText(rate)))
        }
        if let earnedAt = trophy.earnedAt {
            items.append(.label(earnedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "checkmark.circle.fill", tint: AppColors.Status.positiveText))
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

    /// The `InfoTip` on the share of players, where a screen explains it once (the trophy's
    /// facts, the rarest trophies' header), not on every row of a list.
    static var rateInfoTitle: String { String(localized: "trophy.rate.info.title") }
    static var rateInfoMessage: String { String(localized: "trophy.rate.info.message") }
}
