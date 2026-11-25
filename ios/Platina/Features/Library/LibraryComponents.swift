import SwiftUI
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaCore
import PlatinaStore

/// A game in the library: its cover, name, progress, trophy counts and time played.
struct GameRow: View {
    let game: GameRecord
    let status: GamePlanStatus

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            ThumbnailRow(title: game.name) {
                RemotePhoto(key: "game-\(game.id)", url: game.iconURL)
            } details: {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    TrophyCountsLine(earned: game.earned, defined: game.defined)
                    MetaLine(meta)
                        .lineLimit(1)
                }
            }
            GameProgressRing(game: game)
        }
    }

    private var meta: [MetaItem] {
        var items: [MetaItem] = []
        if game.isPS4 {
            items.append(.text(String(localized: "game.platform.ps4")))
        }
        if status != .none {
            items.append(.label(status.title, systemImage: status.systemImage))
        }
        if let seconds = game.playSeconds, seconds > 0 {
            items.append(.label(PlayTimeText.duration(seconds), systemImage: "clock"))
        } else {
            items.append(.text(Formatting.relativeTime(game.lastUpdated)))
        }
        return items
    }
}

/// The game's progress in a ring with the percent inside; platinum-coloured once it has the
/// platinum.
struct GameProgressRing: View {
    let game: GameRecord
    var size: CGFloat = AppIconSize.Tile.sm

    var body: some View {
        ProgressRing(
            progress: Double(game.progress) / 100,
            size: size,
            lineWidth: 4,
            overrideColor: game.isPlatinumEarned ? TrophyType.platinum.color : nil,
            accessibilityLabel: String(localized: "game.progress \(game.progress)"),
            showsTrack: true
        )
        .overlay {
            Text(verbatim: "\(game.progress)%")
                .font(AppTypography.caption2)
                .monospacedDigit()
                .foregroundStyle(AppColors.Text.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// "🏆 1/1 · 12/21 · 2/4 · 22/31": what is earned of each trophy type, platinum first.
struct TrophyCountsLine: View {
    let earned: TrophyCounts
    let defined: TrophyCounts

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(TrophyType.allCases.filter { defined[$0] > 0 }, id: \.self) { type in
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(type.color)
                    Text(verbatim: "\(earned[type])/\(defined[type])")
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("trophy.counts.accessibility \(type.title) \(earned[type]) \(defined[type])"))
            }
        }
        .lineLimit(1)
    }
}

/// The sync's state while it matters: games still loading, PSN asking to wait, a failure.
struct SyncStatusBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.sync.status {
            case .syncing(let done, let total) where total > 0:
                StatusBanner(String(localized: "sync.progress \(done) \(total)"), status: .info, systemImage: "arrow.triangle.2.circlepath")
            case .failed(let error) where error != .sessionExpired && error != .notSignedIn:
                StatusBanner(error.userMessage, status: .warning) {
                    Task { await app.sync.sync(force: true) }
                }
            case .idle where app.sync.pendingGames > 0:
                StatusBanner(String(localized: "sync.pending \(app.sync.pendingGames)"), status: .neutral) {
                    Task { await app.sync.sync(force: true) }
                }
            default:
                EmptyView()
            }
        }
        .animation(AppAnimation.gentleSpring, value: app.sync.status)
    }
}
