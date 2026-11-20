import SwiftUI
import DesignTokens
import DesignComponents
import PSNKit

/// A game: its progress and every trophy, base game and DLC. Stage 0: straight from PSN, no
/// guide yet (docs/PLAN.md §3.3).
struct GameView: View {
    @State private var model: GameModel
    @State private var revealedHidden: Set<Int> = []

    init(title: TrophyTitle, app: AppModel) {
        _model = State(initialValue: GameModel(title: title, client: app.client, onError: { [weak app] error in
            app?.handle(error)
        }))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                GameHeader(title: model.title)

                SegmentedPicker(
                    title: String(localized: "game.filter.title"),
                    selection: $model.filter,
                    options: GameModel.Filter.allCases.map { (label: $0.title, value: $0) }
                )

                content
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.Background.base)
        .navigationTitle(Text(verbatim: model.title.trophyTitleName))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task {
            if model.state == .loading { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .failed(let message):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: String(localized: "game.error.title"),
                description: message,
                actionTitle: String(localized: "common.retry"),
                action: { Task { await model.load() } },
                style: .error
            )
        case .loading:
            CardListSkeleton(layout: .section, count: 6)
        case .loaded:
            let sections = model.sections
            if sections.isEmpty {
                if model.filter == .notEarned {
                    EmptyState(icon: "checkmark.seal", title: String(localized: "game.empty.allEarned"))
                } else {
                    EmptyState(icon: "trophy", title: String(localized: "game.empty.noneEarned"))
                }
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if let group = section.group, model.groups.count > 1 {
                            SectionHeader(
                                group.isBaseGame ? String(localized: "game.group.base") : group.trophyGroupName,
                                style: .compact
                            )
                        }
                        CardList(section.trophies, layout: .section) { trophy in
                            TrophyRow(
                                trophy: trophy,
                                isRevealed: revealedHidden.contains(trophy.id),
                                onReveal: { revealedHidden.insert(trophy.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private extension GameModel.Filter {
    var title: String {
        switch self {
        case .all: String(localized: "game.filter.all")
        case .notEarned: String(localized: "game.filter.notEarned")
        case .earned: String(localized: "game.filter.earned")
        }
    }
}

/// The game's icon, its progress and the trophy counts.
private struct GameHeader: View {
    let title: TrophyTitle

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            RemotePhoto(key: "game-\(title.id)", url: title.iconURL)
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: AppRadius.lg))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(verbatim: "\(title.progress)%")
                    .font(AppTypography.h2)
                    .monospacedDigit()
                    .foregroundStyle(title.isPlatinumEarned ? TrophyType.platinum.color : AppColors.Text.primary)
                LinearProgressBar(
                    value: Double(title.progress) / 100,
                    color: title.isPlatinumEarned ? TrophyType.platinum.color : AppColors.accent
                )
                TrophyCountsLine(earned: title.earnedTrophies, defined: title.definedTrophies)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

/// One trophy: its icon (grey until earned), name, description, rarity and progress. A hidden
/// trophy not earned yet keeps its name and description under a tap, so nothing is spoiled.
private struct TrophyRow: View {
    let trophy: Trophy
    let isRevealed: Bool
    let onReveal: () -> Void

    private var isSpoilerHidden: Bool { trophy.isHidden && !trophy.isEarned && !isRevealed }

    var body: some View {
        ThumbnailRow(title: isSpoilerHidden ? String(localized: "trophy.hidden.title") : trophy.name) {
            if isSpoilerHidden {
                AchievementMedal(systemImage: "questionmark", color: trophy.type.color, isEarned: false, size: 64)
            } else {
                RemotePhoto(key: "trophy-\(trophy.groupId)-\(trophy.id)-\(trophy.iconURL?.lastPathComponent ?? "")", url: trophy.iconURL)
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
                }
                if let progress = trophy.progress, !trophy.isEarned {
                    HStack(spacing: AppSpacing.sm) {
                        LinearProgressBar(value: progress.fraction, color: trophy.type.color, height: 6)
                        Text(verbatim: "\(progress.current)/\(progress.target)")
                            .monospacedDigit()
                    }
                }
                MetaLine(meta)
            }
        }
        .padding(.vertical, AppSpacing.md)
        .rowDividerInset(64 + AppSpacing.md)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSpoilerHidden { onReveal() }
        }
    }

    private var meta: [MetaItem] {
        var items: [MetaItem] = [.label(trophy.type.title, systemImage: trophy.type.systemImage, tint: trophy.type.color)]
        if let rate = trophy.earnedRate {
            items.append(.text(String(localized: "trophy.rate \(rate.formatted(.number.precision(.fractionLength(1))))")))
        }
        if let earnedAt = trophy.earnedAt {
            items.append(.label(earnedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "checkmark.circle.fill", tint: AppColors.success))
        }
        return items
    }
}
