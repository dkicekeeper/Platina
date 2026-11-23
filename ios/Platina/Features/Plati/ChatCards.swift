import SwiftUI
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaAssistant
import PlatinaStore

/// A card Plati drew under its reply (docs/assistant.md §5, display tools). It is drawn from the
/// app's data each time, so a checklist's ticks are the walkthrough's and a trophy shows as it
/// is now.
struct ChatCardView: View {
    let card: ChatCard

    var body: some View {
        switch card {
        case .checklist(let gameId, let chapterId, let stepIds):
            ChatChecklistCard(gameId: gameId, chapterId: chapterId, stepIds: stepIds)
        case .step(let gameId, let chapterId, let stepId):
            ChatStepCard(gameId: gameId, chapterId: chapterId, stepId: stepId)
        case .trophies(let gameId, let trophyIds):
            ChatTrophiesCard(gameId: gameId, trophyIds: trophyIds)
        case .warning(let kind, let title, let text):
            StatusBanner(
                title.map { String(localized: "plati.card.warning \($0) \(text)") } ?? text,
                status: Self.status(of: kind),
                systemImage: Self.systemImage(of: kind)
            )
        case .replies:
            // Drawn as chips under the last reply (ChatView).
            EmptyView()
        }
    }

    private static func status(of kind: String) -> StatusBanner.Status {
        switch kind {
        case "online": .info
        case "other": .neutral
        default: .warning
        }
    }

    private static func systemImage(of kind: String) -> String {
        switch kind {
        case "missable": "exclamationmark.triangle.fill"
        case "choice": "arrow.triangle.branch"
        case "point_of_no_return": "hand.raised.fill"
        case "glitch": "ladybug"
        case "online": "wifi"
        default: "info.circle"
        }
    }
}

/// Steps of a chapter to tick off right in the chat; the ticks are the walkthrough's progress.
private struct ChatChecklistCard: View {
    let gameId: String
    let chapterId: String
    let stepIds: [String]

    @Environment(AppModel.self) private var app
    @State private var revealed: Set<String> = []

    var body: some View {
        let walkthroughs = app.assistant.walkthroughs
        if let chapter = walkthroughs.walkthrough(for: gameId)?.chapter(chapterId),
           let steps = walkthroughs.chapter(gameId: gameId, chapterId: chapterId) {
            let shown = stepIds.compactMap { id in steps.steps.first { $0.id == id } }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label {
                    Text(verbatim: chapter.title)
                } icon: {
                    Icon("checklist", size: AppIconSize.sm)
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.Text.secondary)
                ForEach(shown) { step in
                    let done = walkthroughs.isStepDone(step, gameId: gameId, chapterId: chapterId)
                    let hidden = step.spoiler && !revealed.contains(step.id)
                    ChecklistRow(
                        hidden ? String(localized: "walkthrough.step.spoiler") : WalkthroughText.plain(step.text),
                        isChecked: done,
                        tint: step.kind.tint,
                        accessorySystemImage: step.kind.systemImage,
                        accessoryLabel: step.kind.title,
                        verticalPadding: AppSpacing.sm
                    ) {
                        walkthroughs.setStep(step.id, done: !done, gameId: gameId, chapterId: chapterId)
                    }
                    if hidden {
                        DSButton(String(localized: "walkthrough.step.reveal"), systemImage: "eye", appearance: .flat, size: .small) {
                            revealed.insert(step.id)
                        }
                        .padding(.leading, AppSpacing.xxl + AppSpacing.sm)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
    }
}

/// One step with its picture and video.
private struct ChatStepCard: View {
    let gameId: String
    let chapterId: String
    let stepId: String

    @Environment(AppModel.self) private var app
    @State private var isRevealed = false
    @State private var openedImage: WalkthroughImage?
    @State private var playingVideo: WalkthroughVideo?

    var body: some View {
        let walkthroughs = app.assistant.walkthroughs
        if let steps = walkthroughs.chapter(gameId: gameId, chapterId: chapterId),
           let step = steps.steps.first(where: { $0.id == stepId }) {
            let trophies = ((try? app.store.game(gameId))?.trophies ?? []).filter { step.trophyIds.contains($0.trophyId) }
            WalkthroughStepRow(
                step: step,
                isDone: walkthroughs.isStepDone(step, gameId: gameId, chapterId: chapterId),
                source: steps.source(step.sourceId),
                trophies: trophies,
                isRevealed: isRevealed,
                onReveal: { isRevealed = true },
                onToggle: {
                    let done = walkthroughs.isStepDone(step, gameId: gameId, chapterId: chapterId)
                    walkthroughs.setStep(step.id, done: !done, gameId: gameId, chapterId: chapterId)
                },
                onOpenImage: { openedImage = $0 },
                onPlayVideo: { playingVideo = $0 }
            )
            .padding(AppSpacing.lg)
            .cardStyle()
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
        }
    }
}

/// Trophies as they are now: icon, name (a hidden one stays hidden), progress.
private struct ChatTrophiesCard: View {
    let gameId: String
    let trophyIds: [Int]

    @Environment(AppModel.self) private var app

    var body: some View {
        let all = (try? app.store.game(gameId))?.trophies ?? []
        let trophies = trophyIds.compactMap { id in all.first { $0.trophyId == id } }
        if !trophies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(trophies, id: \.key) { trophy in
                    TrophyRow(trophy: trophy)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .cardStyle()
        }
    }
}
