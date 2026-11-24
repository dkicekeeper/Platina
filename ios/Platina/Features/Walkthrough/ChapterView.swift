import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaAssistant
import PlatinaStore

/// One chapter of the walkthrough (docs/PLAN.md §5): what can be lost here first, then the steps
/// in the order of play as a checklist, each with its picture and video, then the chapter's
/// sources. The current chapter's steps are built when it opens; another chapter's, on a tap
/// (a build costs a model call).
struct ChapterView: View {
    let gameId: String
    let chapterId: String

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @Query private var games: [GameRecord]
    @State private var revealed: Set<String> = []
    @State private var openedImage: WalkthroughImage?
    @State private var playingVideo: WalkthroughVideo?
    @State private var isShowingChat = false

    init(gameId: String, chapterId: String) {
        self.gameId = gameId
        self.chapterId = chapterId
        let id = gameId
        _games = Query(filter: #Predicate<GameRecord> { $0.id == id })
    }

    private var walkthroughs: WalkthroughService { app.assistant.walkthroughs }

    var body: some View {
        Group {
            if let plan = walkthroughs.walkthrough(for: gameId), let chapter = plan.chapter(chapterId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        header(plan: plan, chapter: chapter)
                        warnings(chapter)
                        steps(plan: plan, chapter: chapter)
                        actions(chapter)
                    }
                    .screenPadding()
                    .padding(.bottom, AppSpacing.xxl)
                }
                .navigationTitle(Text(verbatim: chapter.title))
            } else {
                EmptyState(icon: "map", title: String(localized: "walkthrough.chapter.missing"))
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
        }
        .sheet(isPresented: $isShowingChat) {
            GameChatSheet(gameId: gameId, gameName: games.first?.name ?? "")
        }
        .sheet(item: $playingVideo) { video in
            YouTubeVideoSheet(video: video)
        }
        .fullScreenCover(item: $openedImage) { image in
            PhotoViewer([image], selection: image.id) { item in
                RemotePhoto(key: "walkthrough-\(item.url.absoluteString)", url: item.url, contentMode: .fit)
            } caption: { item in
                Text("walkthrough.image.credit \(item.credit)")
            }
        }
        .task(id: chapterId) {
            await walkthroughs.fetchCachedChapter(gameId: gameId, chapterId: chapterId)
            let isCurrent = walkthroughs.position(gameId: gameId)?.currentChapterId == chapterId
            if isCurrent, walkthroughs.chapter(gameId: gameId, chapterId: chapterId) == nil {
                await walkthroughs.buildChapter(gameId: gameId, chapterId: chapterId)
            }
        }
    }

    // MARK: Parts

    private func header(plan: Walkthrough, chapter: Walkthrough.Chapter) -> some View {
        let state = walkthroughs.position(gameId: gameId)?.state(of: chapter.id) ?? .ahead
        let number = (plan.chapters.firstIndex { $0.id == chapter.id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            FlowLayout(spacing: AppSpacing.sm) {
                Badge(String(localized: "walkthrough.chapter.number \(number) \(plan.chapters.count)"), systemImage: "book.pages")
                Badge(state.title, systemImage: state.systemImage, color: state.tint)
                if chapter.playthrough > 1 {
                    Badge(String(localized: "walkthrough.playthrough \(chapter.playthrough)"), systemImage: "arrow.trianglehead.2.clockwise", color: AppColors.Status.neutral)
                }
            }
            if !chapter.summary.isEmpty {
                Text(verbatim: chapter.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.Text.primary)
            }
            if !chapter.collectibles.isEmpty {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(chapter.collectibles, id: \.kind) { item in
                        Badge(String(localized: "walkthrough.collectibles \(item.kind) \(item.count)"), systemImage: "sparkles", color: AppColors.Status.info)
                    }
                }
            }
        }
    }

    /// What can be lost here for good: missable things and choices, before anything else.
    @ViewBuilder
    private func warnings(_ chapter: Walkthrough.Chapter) -> some View {
        if chapter.hasWarnings {
            let trophies = games.first?.trophies ?? []
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                StatusBanner(String(localized: "walkthrough.chapter.warning"), status: .warning, systemImage: "exclamationmark.triangle.fill")
                ForEach(Array(chapter.missable.enumerated()), id: \.offset) { _, missable in
                    let trophy = missable.trophyId.flatMap { id in trophies.first { $0.trophyId == id } }
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        if let trophy {
                            Label {
                                Text(verbatim: trophy.isHidden && !trophy.isEarned ? String(localized: "trophy.hidden.title") : trophy.name)
                                    .strikethrough(trophy.isEarned)
                            } icon: {
                                Icon(trophy.isEarned ? "checkmark.circle.fill" : trophy.type.systemImage, size: AppIconSize.sm, tint: .monochrome(trophy.isEarned ? AppColors.success : trophy.type.color))
                            }
                            .font(AppTypography.bodyEmphasis)
                        }
                        Text(verbatim: missable.note)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.Text.secondary)
                    }
                }
                ForEach(chapter.choices, id: \.self) { choice in
                    Label {
                        Text(verbatim: choice)
                    } icon: {
                        Icon("arrow.triangle.branch", size: AppIconSize.sm, tint: .monochrome(AppColors.warning))
                    }
                    .font(AppTypography.bodySmall)
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }

    @ViewBuilder
    private func steps(plan: Walkthrough, chapter: Walkthrough.Chapter) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "walkthrough.steps.header"), systemImage: "checklist")
            if let steps = walkthroughs.chapter(gameId: gameId, chapterId: chapter.id) {
                stepList(steps)
            } else {
                switch walkthroughs.state(for: gameId, chapterId: chapter.id) {
                case .building(let step):
                    WalkthroughBuildingCard(step: step)
                case .failed(let code):
                    StatusBanner(WalkthroughText.failure(code, steps: true), status: .warning) {
                        Task { await walkthroughs.buildChapter(gameId: gameId, chapterId: chapter.id) }
                    }
                case .idle:
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("walkthrough.steps.empty")
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.Text.secondary)
                        DSButton(String(localized: "walkthrough.steps.build"), systemImage: "sparkles", appearance: .secondary, fullWidth: true) {
                            Task { await walkthroughs.buildChapter(gameId: gameId, chapterId: chapter.id) }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .cardStyle()
                }
            }
        }
    }

    @ViewBuilder
    private func stepList(_ chapter: ChapterSteps) -> some View {
        let trophies = games.first?.trophies ?? []
        let done = chapter.steps.map { walkthroughs.isStepDone($0, gameId: gameId, chapterId: chapter.chapterId) }
        let doneCount = done.filter { $0 }.count
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ChecklistSummaryRow(
                title: String(localized: "walkthrough.steps.progress"),
                checked: doneCount,
                total: chapter.steps.count,
                progressText: String(localized: "walkthrough.steps.count \(doneCount) \(chapter.steps.count)")
            )
            ForEach(Array(chapter.steps.enumerated()), id: \.element.id) { index, step in
                WalkthroughStepRow(
                    step: step,
                    isDone: done[index],
                    source: chapter.source(step.sourceId),
                    trophies: trophies.filter { step.trophyIds.contains($0.trophyId) },
                    isRevealed: revealed.contains(step.id),
                    onReveal: { revealed.insert(step.id) },
                    onToggle: {
                        walkthroughs.setStep(step.id, done: !done[index], gameId: gameId, chapterId: chapter.chapterId)
                    },
                    onOpenImage: { openedImage = $0 },
                    onPlayVideo: { playingVideo = $0 }
                )
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .completionMoment(isComplete: !done.isEmpty && doneCount == done.count, in: RoundedRectangle(cornerRadius: AppRadius.xl))

        if !chapter.sources.isEmpty {
            FormSection(header: String(localized: "guide.sources"), footer: String(localized: "walkthrough.sources.footer")) {
                ForEach(chapter.sources) { source in
                    UniversalRow(source.title, icon: "link", accessory: .action {
                        if let url = URL(string: source.url) { openURL(url) }
                    })
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ chapter: Walkthrough.Chapter) -> some View {
        let state = walkthroughs.position(gameId: gameId)?.state(of: chapter.id) ?? .ahead
        VStack(spacing: AppSpacing.md) {
            if let next = walkthroughs.currentStep(gameId: gameId), next.chapter.id == chapter.id {
                DSButton(String(localized: "walkthrough.speak"), systemImage: "speaker.wave.2", appearance: .secondary, fullWidth: true) {
                    let text = next.step.spoiler ? String(localized: "intent.step.spoiler") : WalkthroughText.plain(next.step.text)
                    StepSpeaker.shared.speak(text)
                }
            }
            if state != .done {
                DSButton(String(localized: "walkthrough.chapter.finish"), systemImage: "flag.checkered", fullWidth: true) {
                    walkthroughs.setChapter(chapter.id, done: true, gameId: gameId)
                    AccessibilityAnnouncer.announce(String(localized: "walkthrough.chapter.finished"))
                }
            }
            if state != .current {
                DSButton(String(localized: "walkthrough.chapter.here"), systemImage: "mappin.and.ellipse", appearance: .secondary, fullWidth: true) {
                    walkthroughs.setCurrentChapter(chapter.id, gameId: gameId)
                }
            }
            if walkthroughs.chapter(gameId: gameId, chapterId: chapter.id) != nil {
                DSButton(String(localized: "walkthrough.steps.rebuild"), systemImage: "arrow.clockwise", appearance: .flat, size: .small) {
                    Task { await walkthroughs.buildChapter(gameId: gameId, chapterId: chapter.id, refresh: true) }
                }
            }
        }
    }
}
