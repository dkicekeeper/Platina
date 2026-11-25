import SwiftUI
import SwiftData
import DesignTokens
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// The PS5 games: shelves, an order, search (docs/PLAN.md §3.2). On an iPad or in a Mac window
/// the list and the open game stand side by side (`NavigationSplitView`, stage 10); on a phone the
/// split view collapses into a stack, the list first.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \GameRecord.lastUpdated, order: .reverse) private var games: [GameRecord]
    @Query private var plans: [GamePlanRecord]

    /// nil: every game (the chips' "All").
    @State private var shelf: GameShelf?
    @State private var sort: GameSort = .recent
    @State private var query = ""
    @State private var openedGame: String? = ScreenshotDemo.screen?.opensGame == true ? ScreenshotDemo.gameId : nil
    /// What a collapsed split view (a phone) shows: the list, or the open game over it.
    @State private var compactColumn: NavigationSplitViewColumn = ScreenshotDemo.screen?.opensGame == true ? .detail : .sidebar

    private var statuses: [String: GamePlanStatus] {
        Dictionary(plans.map { ($0.gameId, $0.status) }, uniquingKeysWith: { first, _ in first })
    }

    private var summaries: [GameSummary] {
        let lookup = statuses
        return games.map { $0.summary(status: lookup[$0.id] ?? .none) }
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            list
        } detail: {
            NavigationStack {
                if ScreenshotDemo.screen == .chapter {
                    // The App Store's screenshot of the current chapter.
                    ChapterView(gameId: ScreenshotDemo.gameId, chapterId: ScreenshotDemo.chapterId)
                } else if let openedGame {
                    // A game of its own each time: its sections, filters and loading start over.
                    GameView(gameId: openedGame)
                        .id(openedGame)
                } else {
                    EmptyState(
                        icon: "square.stack",
                        title: String(localized: "library.pick.title"),
                        description: String(localized: "library.pick.message")
                    )
                    .screenPadding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.Background.base)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                SyncStatusBanner()
                content
            }
            .screenPadding()
            .readableWidth()
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.Background.base)
        .navigationTitle(Text("library.title"))
        .searchable(text: $query, prompt: Text("library.search"))
        .refreshable { await app.sync.sync(force: true) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $sort) {
                        ForEach(GameSort.allCases) { sort in
                            Text(sort.title).tag(sort)
                        }
                    } label: {
                        Text("library.sort")
                    }
                } label: {
                    Label(String(localized: "library.sort"), systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }

    private func open(_ gameId: String) {
        openedGame = gameId
        compactColumn = .detail
    }

    @ViewBuilder
    private var content: some View {
        if games.isEmpty {
            emptyLibrary
        } else {
            let all = summaries
            let counts = all.counts()
            ChipPicker(
                options: GameShelf.allCases.filter { $0 != .all },
                selection: $shelf,
                allTitle: String(localized: "shelf.all.count \(counts[.all] ?? 0)")
            ) { shelf in
                String(localized: "shelf.chip \(shelf.title) \(counts[shelf] ?? 0)")
            }

            let visible = all.filtered(shelf: shelf ?? .all, query: query, sort: sort)
            if visible.isEmpty {
                EmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: String(localized: "library.noMatches.title"),
                    description: String(localized: "library.noMatches.message")
                )
            } else {
                let byId = Dictionary(games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                CardList(visible, layout: .cards, onOpen: { open($0.id) }) { (summary: GameSummary) in
                    if let game = byId[summary.id] {
                        GameRow(game: game, status: summary.status)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyLibrary: some View {
        switch app.sync.status {
        case .failed(let error):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: String(localized: "library.error.title"),
                description: error.userMessage,
                actionTitle: String(localized: "common.retry"),
                action: { Task { await app.sync.sync(force: true) } },
                style: .error
            )
        case .syncing:
            VStack(spacing: AppSpacing.md) {
                ChipPickerSkeleton(showsTitle: false)
                CardListSkeleton(layout: .cards, count: 5)
            }
        case .idle:
            if app.sync.lastSyncedAt == nil {
                CardListSkeleton(layout: .cards, count: 5)
            } else {
                EmptyState(
                    icon: "gamecontroller",
                    title: String(localized: "library.empty.title"),
                    description: String(localized: "library.empty.message")
                )
            }
        }
    }
}
