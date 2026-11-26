import SwiftUI
import WidgetKit
import DesignTokens
import PlatinaShared

/// Reads the snapshot the app writes after each sync; the app asks for a redraw itself.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.read() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshotStore.read())
        // The app reloads after every sync; a slow refresh in between keeps "updated" honest.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - The road to platinum

/// The games the person goes for: the first one in a small widget and on the lock screen, up to
/// three in a medium one.
struct PlatinumProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PlatinumProgress", provider: SnapshotProvider()) { entry in
            PlatinumProgressView(entry: entry)
                .containerBackground(AppColors.Background.page, for: .widget)
        }
        .configurationDisplayName(Text(verbatim: "Platina"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct PlatinumProgressView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let first = snapshot.games.first {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(first.progress), in: 0...100) {
                    Image(systemName: "trophy.fill")
                } currentValueLabel: {
                    Text(verbatim: "\(first.progress)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(verbatim: first.name).font(AppTypography.bodyEmphasis).lineLimit(1)
                    ProgressView(value: Double(first.progress), total: 100)
                    Text(verbatim: "\(first.progress)% · \(first.detail)").font(AppTypography.caption).lineLimit(1)
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Header(title: snapshot.title("chase"))
                    ForEach(snapshot.games) { game in
                        GameLine(game: game)
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Header(title: snapshot.title("chase"))
                    Spacer(minLength: 0)
                    ProgressRingView(progress: first.progress)
                    Text(verbatim: first.name)
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(verbatim: first.detail)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.Text.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            EmptySnapshotView(text: entry.snapshot?.title("empty"))
        }
    }
}

private struct Header: View {
    let title: String

    var body: some View {
        Label {
            Text(verbatim: title).lineLimit(1)
        } icon: {
            Image(systemName: "trophy.fill").foregroundStyle(AppColors.accent)
        }
        .font(AppTypography.caption)
        .foregroundStyle(AppColors.Text.secondary)
    }
}

private struct GameLine: View {
    let game: WidgetSnapshot.Game

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack {
                Text(verbatim: game.name)
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.xs)
                Text(verbatim: "\(game.progress)%")
                    .font(AppTypography.caption)
                    .monospacedDigit()
            }
            ProgressView(value: Double(game.progress), total: 100)
                .tint(AppColors.accent)
        }
    }
}

private struct ProgressRingView: View {
    let progress: Int

    var body: some View {
        ZStack {
            Circle().stroke(AppColors.accent.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(progress) / 100)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(progress)%")
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .frame(width: 52, height: 52)
    }
}

private struct EmptySnapshotView: View {
    let text: String?

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: "trophy")
                .font(AppTypography.h3)
                .foregroundStyle(AppColors.accent)
            Text(verbatim: text ?? "Platina")
                .font(AppTypography.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColors.Text.secondary)
        }
    }
}

// MARK: - The latest trophy

struct LatestTrophyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestTrophy", provider: SnapshotProvider()) { entry in
            LatestTrophyView(entry: entry)
                .containerBackground(AppColors.Background.page, for: .widget)
        }
        .configurationDisplayName(Text(verbatim: "Platina"))
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct LatestTrophyView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let trophy = snapshot.latestTrophy {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Label(trophy.name, systemImage: "trophy.fill").font(AppTypography.bodyEmphasis).lineLimit(1)
                    Text(verbatim: trophy.gameName).font(AppTypography.caption).lineLimit(1)
                    Text(trophy.earnedAt, style: .relative).font(AppTypography.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Header(title: snapshot.title("latest"))
                    Spacer(minLength: 0)
                    Image(systemName: "trophy.fill")
                        .font(AppTypography.h2)
                        .foregroundStyle(PlatinaPalette.metal(trophy.type))
                    Text(verbatim: trophy.name)
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    Text(verbatim: trophy.gameName)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.Text.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            EmptySnapshotView(text: entry.snapshot?.title("empty"))
        }
    }
}
