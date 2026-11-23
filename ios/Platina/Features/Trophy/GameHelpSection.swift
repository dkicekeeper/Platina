import SwiftUI
import AVKit
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaStore

/// PlayStation's own help for a trophy, when it has some: the steps in words, each with its
/// video. Shows nothing for a trophy without help.
struct GameHelpSection: View {
    let trophy: TrophyRecord
    @Environment(AppModel.self) private var app
    @State private var phase = Phase.checking
    @State private var playing: PlayingVideo?

    private enum Phase: Equatable {
        case checking
        case none
        case loading
        case loaded(GameHelp)
    }

    var body: some View {
        Group {
            switch phase {
            case .checking, .none:
                EmptyView()
            case .loading, .loaded:
                card {
                    SkeletonReveal(isLoading: phase == .loading) {
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            ForEach(tips) { tip in
                                tipView(tip)
                            }
                        }
                    } skeleton: {
                        ArticleBodySkeleton(paragraphs: 2)
                    }
                }
            }
        }
        .task(id: trophy.key) { await load() }
        .fullScreenCover(item: $playing) { video in
            VideoSheet(url: video.url)
        }
    }

    private var tips: [GameHelpTip] {
        guard case .loaded(let help) = phase else { return [] }
        return help.tips
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "trophy.gameHelp.header"), systemImage: "questionmark.bubble")
            content()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    @ViewBuilder
    private func tipView(_ tip: GameHelpTip) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let title = tip.title {
                Text(verbatim: title)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.Text.primary)
            }
            if let text = tip.text {
                ArticleBody(ArticleBody.Block.parse(markdown: text))
            }
            if let url = tip.videoURL {
                DSButton(String(localized: "trophy.gameHelp.video"), systemImage: "play.fill", appearance: .flat, size: .small) {
                    playing = PlayingVideo(url: url)
                }
            }
        }
    }

    private func load() async {
        phase = .checking
        guard await app.gameHelp.hasHelp(gameId: trophy.gameId, trophyId: trophy.trophyId) else {
            phase = .none
            return
        }
        phase = .loading
        if let help = await app.gameHelp.help(gameId: trophy.gameId, trophyId: trophy.trophyId) {
            phase = .loaded(help)
        } else {
            phase = .none
        }
    }
}

private struct PlayingVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

/// A Game Help video, full screen, with the system's player controls.
private struct VideoSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.close")) { dismiss() }
                    }
                }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
