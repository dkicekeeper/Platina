import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaAssistant
import PlatinaStore

/// A game's walkthrough on its screen (docs/PLAN.md §5): the chapter to play now, how far along
/// the person is, what this chapter can lose, and the way to every chapter. Built by Plati's
/// server when the person asks for it (a model call), or when Plati needs it.
struct WalkthroughSection: View {
    let game: GameRecord
    @Environment(AppModel.self) private var app

    var body: some View {
        let walkthroughs = app.assistant.walkthroughs
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let plan = walkthroughs.walkthrough(for: game.id) {
                SectionHeader(String(localized: "walkthrough.header"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                    NavigationLink {
                        WalkthroughView(gameId: game.id)
                    } label: {
                        Text("walkthrough.all \(plan.chapters.count)")
                    }
                }
                current(plan, walkthroughs: walkthroughs)
            } else {
                SectionHeader(String(localized: "walkthrough.header"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                switch walkthroughs.state(for: game.id) {
                case .building(let step):
                    WalkthroughBuildingCard(step: step)
                case .failed(let code):
                    StatusBanner(WalkthroughText.failure(code, steps: false), status: .warning) {
                        Task { await walkthroughs.build(gameId: game.id) }
                    }
                case .idle:
                    if walkthroughs.isAvailable {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("walkthrough.empty")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.Text.secondary)
                            DSButton(String(localized: "walkthrough.build"), systemImage: "sparkles", appearance: .secondary, fullWidth: true) {
                                Task { await walkthroughs.build(gameId: game.id) }
                            }
                        }
                        .padding(AppSpacing.lg)
                        .cardStyle()
                    }
                }
            }
        }
        .task { await walkthroughs.fetchCached(gameId: game.id) }
    }

    @ViewBuilder
    private func current(_ plan: Walkthrough, walkthroughs: WalkthroughService) -> some View {
        let position = walkthroughs.position(gameId: game.id)
        let done = plan.chapters.filter { position?.state(of: $0.id) == .done }.count
        if let id = position?.currentChapterId, let chapter = plan.chapter(id) {
            let number = (plan.chapters.firstIndex { $0.id == id } ?? 0) + 1
            NavigationLink {
                ChapterView(gameId: game.id, chapterId: chapter.id)
            } label: {
                CurrentChapterCard(
                    chapter: chapter,
                    number: number,
                    total: plan.chapters.count,
                    done: done,
                    nextStep: nextStep(chapterId: chapter.id, walkthroughs: walkthroughs)
                )
            }
            .buttonStyle(.plain)
        } else {
            // Every chapter behind: the cleanup is what is left.
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                StatusBanner(String(localized: "walkthrough.storyDone"), status: .positive, systemImage: "flag.checkered")
                if !plan.cleanup.isEmpty {
                    ArticleBody(ArticleBody.Block.parse(markdown: plan.cleanup))
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }

    private func nextStep(chapterId: String, walkthroughs: WalkthroughService) -> ChapterSteps.Step? {
        guard let steps = walkthroughs.chapter(gameId: game.id, chapterId: chapterId) else { return nil }
        return steps.steps.first { !walkthroughs.isStepDone($0, gameId: game.id, chapterId: chapterId) }
    }
}

/// The chapter to play now: its number, title and summary, the way through the game, what can be
/// lost in it, and the next step when the steps are built.
private struct CurrentChapterCard: View {
    let chapter: Walkthrough.Chapter
    let number: Int
    let total: Int
    let done: Int
    let nextStep: ChapterSteps.Step?
    @AppStorage(DisplaySettings.spoilersKey) private var showsSpoilers = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Badge(String(localized: "walkthrough.chapter.number \(number) \(total)"), systemImage: "play.fill")
                Spacer(minLength: 0)
                DisclosureChevron()
            }
            Text(verbatim: chapter.title)
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.Text.primary)
            if !chapter.summary.isEmpty {
                Text(verbatim: chapter.summary)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.Text.secondary)
            }
            LinearProgressBar(value: total > 0 ? Double(done) / Double(total) : 0)
                .accessibilityLabel(Text("walkthrough.progress \(done) \(total)"))
            if chapter.hasWarnings {
                StatusBanner(
                    String(localized: "walkthrough.chapter.warnings \(chapter.missable.count + chapter.choices.count)"),
                    status: .warning,
                    style: .compact,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            if let nextStep {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("walkthrough.next")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                    Text(verbatim: nextStep.spoiler && !showsSpoilers ? String(localized: "walkthrough.step.spoiler") : WalkthroughText.plain(nextStep.text))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.Text.primary)
                        .lineLimit(3)
                }
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .contentShape(Rectangle())
    }
}

/// Every chapter of a game's walkthrough, by playthrough, with where the person is; the route's
/// overview, the cleanup and the sources.
struct WalkthroughView: View {
    let gameId: String
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let walkthroughs = app.assistant.walkthroughs
        Group {
            if let plan = walkthroughs.walkthrough(for: gameId) {
                let position = walkthroughs.position(gameId: gameId)
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        overview(plan, position: position)
                        collectibles(walkthroughs.collectibles(gameId: gameId))
                        ForEach(playthroughs(plan), id: \.self) { playthrough in
                            chapters(plan, playthrough: playthrough, position: position, titled: playthroughs(plan).count > 1)
                        }
                        if !plan.cleanup.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.md) {
                                SectionHeader(String(localized: "walkthrough.cleanup"), systemImage: "sparkles")
                                ArticleBody(ArticleBody.Block.parse(markdown: plan.cleanup))
                                    .padding(AppSpacing.lg)
                                    .cardStyle()
                            }
                        }
                        if !plan.sources.isEmpty {
                            FormSection(header: String(localized: "guide.sources"), footer: String(localized: "walkthrough.sources.footer")) {
                                ForEach(plan.sources) { source in
                                    UniversalRow(source.title, icon: "link", accessory: .action {
                                        if let url = URL(string: source.url) { openURL(url) }
                                    })
                                }
                            }
                        }
                        DSButton(String(localized: "walkthrough.rebuild"), systemImage: "arrow.clockwise", appearance: .flat, size: .small) {
                            Task { await walkthroughs.build(gameId: gameId, refresh: true) }
                        }
                    }
                    .screenPadding()
                    .padding(.bottom, AppSpacing.xxl)
                }
            } else {
                EmptyState(icon: "map", title: String(localized: "walkthrough.chapter.missing"))
                    .screenPadding()
            }
        }
        .background(AppColors.Background.base)
        .navigationTitle(Text("walkthrough.header"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Every kind of collectible in the game: found of how many.
    @ViewBuilder
    private func collectibles(_ tally: [CollectibleTally]) -> some View {
        if !tally.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "walkthrough.collectibles.header"), systemImage: "sparkles")
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ForEach(tally) { item in
                        ChecklistSummaryRow(
                            title: item.kind,
                            checked: item.found,
                            total: item.total,
                            progressText: String(localized: "walkthrough.steps.count \(item.found) \(item.total)")
                        )
                    }
                    Text("walkthrough.collectibles.footer")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
        }
    }

    private func playthroughs(_ plan: Walkthrough) -> [Int] {
        Array(Set(plan.chapters.map(\.playthrough))).sorted()
    }

    private func overview(_ plan: Walkthrough, position: WalkthroughPosition?) -> some View {
        let done = plan.chapters.filter { position?.state(of: $0.id) == .done }.count
        var items: [StatsStrip.Item] = [
            .init(value: plan.chapters.count.formatted(), title: String(localized: "walkthrough.stat.chapters")),
            .init(value: done.formatted(), title: String(localized: "walkthrough.stat.done")),
        ]
        if let playthroughs = plan.playthroughs {
            items.append(.init(value: playthroughs.formatted(), title: String(localized: "guide.playthroughs")))
        }
        return VStack(alignment: .leading, spacing: AppSpacing.lg) {
            StatsStrip(items: items)
            if !plan.overview.isEmpty {
                ExpandableText(plan.overview, lineLimit: 4, font: AppTypography.bodySmall)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    private func chapters(_ plan: Walkthrough, playthrough: Int, position: WalkthroughPosition?, titled: Bool) -> some View {
        let chapters = plan.chapters.filter { $0.playthrough == playthrough }
        return FormSection(header: titled ? String(localized: "walkthrough.playthrough \(playthrough)") : nil) {
            ForEach(chapters) { chapter in
                let state = position?.state(of: chapter.id) ?? .ahead
                NavigationLink {
                    ChapterView(gameId: gameId, chapterId: chapter.id)
                } label: {
                    ItemRow(
                        chapter.title,
                        detail: chapter.summary.isEmpty ? nil : chapter.summary,
                        meta: meta(chapter, state: state),
                        leading: .symbol(state.systemImage, tint: state.tint)
                    ) {
                        DisclosureChevron()
                    }
                }
                .buttonStyle(.plain)
                .rowDividerInset(ItemRowStyle.standard.symbolDividerInset)
            }
        }
    }

    private func meta(_ chapter: Walkthrough.Chapter, state: WalkthroughPosition.ChapterState) -> [MetaLine] {
        var items: [MetaItem] = [.label(state.title, systemImage: state.systemImage, tint: state.tint)]
        let warnings = chapter.missable.count + chapter.choices.count
        if warnings > 0 {
            items.append(.label(String(localized: "walkthrough.chapter.warnings \(warnings)"), systemImage: "exclamationmark.triangle.fill", tint: AppColors.warning))
        }
        let collectibles = chapter.collectibles.reduce(0) { $0 + $1.count }
        if collectibles > 0 {
            items.append(.label(String(localized: "walkthrough.collectibles.total \(collectibles)"), systemImage: "sparkles", tint: AppColors.Status.info))
        }
        return [MetaLine(items)]
    }
}

/// The walkthrough in a running session: the chapter now and its next steps, ticked off right
/// here, and the way into the chapter. Nothing when the game has no walkthrough.
struct SessionChapterCard: View {
    let gameId: String
    @Environment(AppModel.self) private var app
    @AppStorage(DisplaySettings.spoilersKey) private var showsSpoilers = false

    var body: some View {
        let walkthroughs = app.assistant.walkthroughs
        if let plan = walkthroughs.walkthrough(for: gameId),
           let id = walkthroughs.position(gameId: gameId)?.currentChapterId,
           let chapter = plan.chapter(id) {
            let steps = walkthroughs.chapter(gameId: gameId, chapterId: id)
            let next = (steps?.steps ?? []).filter { !walkthroughs.isStepDone($0, gameId: gameId, chapterId: id) }.prefix(3)
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "walkthrough.session.header"), systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") {
                    NavigationLink {
                        ChapterView(gameId: gameId, chapterId: id)
                    } label: {
                        Text("walkthrough.session.open")
                    }
                }
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(verbatim: chapter.title)
                        .font(AppTypography.bodyEmphasis)
                    if chapter.hasWarnings {
                        StatusBanner(
                            String(localized: "walkthrough.chapter.warnings \(chapter.missable.count + chapter.choices.count)"),
                            status: .warning,
                            style: .compact,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                    }
                    if steps == nil {
                        Text("walkthrough.session.noSteps")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.Text.secondary)
                    }
                    ForEach(Array(next)) { step in
                        ChecklistRow(
                            step.spoiler && !showsSpoilers ? String(localized: "walkthrough.step.spoiler") : WalkthroughText.plain(step.text),
                            isChecked: false,
                            tint: step.kind.tint,
                            accessorySystemImage: step.kind.systemImage,
                            accessoryLabel: step.kind.title,
                            verticalPadding: AppSpacing.sm
                        ) {
                            walkthroughs.setStep(step.id, done: true, gameId: gameId, chapterId: id)
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .cardStyle()
            }
            .task(id: id) { await walkthroughs.fetchCachedChapter(gameId: gameId, chapterId: id) }
        }
    }
}
