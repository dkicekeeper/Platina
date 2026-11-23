import SwiftUI
import WebKit
import AVFoundation
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaAssistant
import PlatinaStore

// The pieces of the walkthrough's screens (docs/PLAN.md §5, «Прохождение по главам»): how a
// step's kind and a chapter's state look, a step's row with its picture and video, the build's
// progress, the YouTube player.

extension ChapterSteps.Step.Kind {
    var title: String {
        switch self {
        case .path: String(localized: "walkthrough.kind.path")
        case .collectible: String(localized: "walkthrough.kind.collectible")
        case .choice: String(localized: "walkthrough.kind.choice")
        case .pointOfNoReturn: String(localized: "walkthrough.kind.pointOfNoReturn")
        case .trophy: String(localized: "walkthrough.kind.trophy")
        case .boss: String(localized: "walkthrough.kind.boss")
        case .tip: String(localized: "walkthrough.kind.tip")
        }
    }

    var systemImage: String {
        switch self {
        case .path: "arrow.turn.up.right"
        case .collectible: "sparkles"
        case .choice: "arrow.triangle.branch"
        case .pointOfNoReturn: "exclamationmark.triangle.fill"
        case .trophy: "trophy.fill"
        case .boss: "bolt.shield"
        case .tip: "lightbulb"
        }
    }

    var tint: Color {
        switch self {
        case .path, .tip: AppColors.accent
        case .collectible: AppColors.Status.info
        case .choice, .pointOfNoReturn: AppColors.warning
        case .trophy: AppColors.success
        case .boss: AppColors.destructive
        }
    }
}

extension WalkthroughPosition.ChapterState {
    var title: String {
        switch self {
        case .done: String(localized: "walkthrough.state.done")
        case .current: String(localized: "walkthrough.state.current")
        case .ahead: String(localized: "walkthrough.state.ahead")
        }
    }

    var systemImage: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .current: "play.circle.fill"
        case .ahead: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .done: AppColors.success
        case .current: AppColors.accent
        case .ahead: AppColors.Text.tertiary
        }
    }
}

enum WalkthroughText {
    /// A step's Markdown as plain text, for a checklist row.
    static func plain(_ markdown: String) -> String {
        guard let attributed = try? AttributedString(markdown: markdown) else { return markdown }
        return String(attributed.characters)
    }

    static func buildStep(_ step: String) -> String {
        switch step {
        case "search": String(localized: "walkthrough.build.search")
        case "reading": String(localized: "walkthrough.build.reading")
        case "writing": String(localized: "walkthrough.build.writing")
        default: String(localized: "walkthrough.build.start")
        }
    }

    static func buildProgress(_ step: String) -> Double {
        switch step {
        case "search": 0.3
        case "reading": 0.55
        case "writing": 0.8
        default: 0.1
        }
    }
}

/// A build on the server: Plati at work and what it is doing.
struct WalkthroughBuildingCard: View {
    let step: String

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ParticleCreature(mood: .working(progress: WalkthroughText.buildProgress(step)), style: .compact)
                .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)
                .accessibilityHidden(true)
            Text(verbatim: WalkthroughText.buildStep(step))
                .font(AppTypography.bodySmall)
                .thinkingShimmer()
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// A picture from a guide, shown full screen with its source.
struct WalkthroughImage: Identifiable, Hashable {
    let url: URL
    let credit: String
    var id: String { url.absoluteString }
}

/// A YouTube video of a step, played in the app.
struct WalkthroughVideo: Identifiable, Hashable {
    let youtubeId: String
    let startSeconds: Int
    let credit: String?
    var id: String { "\(youtubeId)@\(startSeconds)" }
}

/// One step: a tick, its text (behind a tap when it spoils), and what goes with it: the
/// collectible's number, the trophies, the picture of the spot, the video.
struct WalkthroughStepRow: View {
    let step: ChapterSteps.Step
    let isDone: Bool
    let source: Guide.Source?
    let trophies: [TrophyRecord]
    let isRevealed: Bool
    let onReveal: () -> Void
    let onToggle: () -> Void
    let onOpenImage: (WalkthroughImage) -> Void
    let onPlayVideo: (WalkthroughVideo) -> Void

    private var isHidden: Bool { step.spoiler && !isRevealed }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            if step.kind.isWarning && !isDone && !isHidden {
                StatusBanner(step.kind.title, status: .warning, style: .compact, systemImage: step.kind.systemImage)
            }
            ChecklistRow(
                isHidden ? String(localized: "walkthrough.step.spoiler") : WalkthroughText.plain(step.text),
                isChecked: isDone,
                tint: step.kind.tint,
                accessorySystemImage: step.kind.systemImage,
                accessoryLabel: step.kind.title,
                verticalPadding: AppSpacing.sm,
                onToggle: onToggle
            )
            details
                .padding(.leading, AppSpacing.xxl + AppSpacing.sm)
        }
    }

    @ViewBuilder
    private var details: some View {
        if isHidden {
            DSButton(String(localized: "walkthrough.step.reveal"), systemImage: "eye", appearance: .flat, size: .small, action: onReveal)
        } else {
            let badges = badgeItems
            if !badges.isEmpty {
                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(badges, id: \.text) { badge in
                        Badge(badge.text, systemImage: badge.systemImage, color: badge.color)
                    }
                }
            }
            if let image = step.image, let url = URL(string: image.url) {
                let credit = source?.title ?? url.host() ?? ""
                Button {
                    onOpenImage(WalkthroughImage(url: url, credit: credit))
                } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        RemotePhoto(key: "walkthrough-\(image.url)", url: url)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        Text("walkthrough.image.credit \(credit)")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.Text.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("walkthrough.image.open \(credit)"))
            }
            if let video = step.video {
                DSButton(String(localized: "walkthrough.step.video"), systemImage: "play.rectangle.fill", appearance: .flat, size: .small) {
                    onPlayVideo(WalkthroughVideo(youtubeId: video.youtubeId, startSeconds: video.startSeconds, credit: source?.title))
                }
            }
        }
    }

    private struct BadgeItem {
        let text: String
        let systemImage: String
        let color: Color
    }

    private var badgeItems: [BadgeItem] {
        var items: [BadgeItem] = []
        if let collectible = step.collectible {
            items.append(.init(
                text: String(localized: "walkthrough.collectible \(collectible.kind) \(collectible.number)"),
                systemImage: "sparkles",
                color: AppColors.Status.info
            ))
        }
        for trophy in trophies {
            let name = trophy.isHidden && !trophy.isEarned ? String(localized: "trophy.hidden.title") : trophy.name
            items.append(.init(text: name, systemImage: trophy.type.systemImage, color: trophy.type.color))
        }
        return items
    }
}

/// A YouTube video in the app's own player (an embedded player, as YouTube asks of apps).
struct YouTubeVideoSheet: View {
    let video: WalkthroughVideo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                YouTubePlayer(video: video)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                if let credit = video.credit {
                    Text("walkthrough.video.credit \(credit)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                }
                DSButton(String(localized: "walkthrough.video.openYouTube"), systemImage: "arrow.up.forward.app", appearance: .secondary, fullWidth: true) {
                    if let url = URL(string: "https://www.youtube.com/watch?v=\(video.youtubeId)&t=\(video.startSeconds)s") {
                        openURL(url)
                    }
                }
                Spacer(minLength: 0)
            }
            .screenPadding()
            .padding(.top, AppSpacing.lg)
            .background(AppColors.Background.base)
            .navigationTitle(Text("walkthrough.video.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct YouTubePlayer: UIViewRepresentable {
    let video: WalkthroughVideo

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        // YouTube's embedded player wants to know which app plays it: the page's origin is the
        // app's id, as YouTube's terms for apps ask.
        let id = video.youtubeId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:black}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(id)?start=\(max(video.startSeconds, 0))&playsinline=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://dakacom.platina"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// Reads a step aloud, in the app's language: the controller in the hands, the phone on the sofa.
@MainActor
final class StepSpeaker {
    static let shared = StepSpeaker()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AppLanguage.code == "en" ? "en-US" : "ru-RU")
        synthesizer.speak(utterance)
    }
}
