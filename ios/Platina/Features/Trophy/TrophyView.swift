import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaStore

/// One trophy (docs/PLAN.md §3.4): the icon (a holographic foil for the platinum), how rare it
/// is, when it was earned, its progress, PlayStation's Game Help, Plati's tip and the person's note.
struct TrophyView: View {
    @Environment(AppModel.self) private var app
    @Query private var trophies: [TrophyRecord]
    @State private var note = ""

    init(trophyKey: String) {
        let key = trophyKey
        _trophies = Query(filter: #Predicate<TrophyRecord> { $0.key == key })
    }

    var body: some View {
        Group {
            if let trophy = trophies.first {
                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        TrophyHero(trophy: trophy)
                        VStack(spacing: AppSpacing.sm) {
                            Text(verbatim: trophy.name)
                                .font(AppTypography.h3)
                                .foregroundStyle(AppColors.Text.primary)
                                .multilineTextAlignment(.center)
                            if !trophy.detail.isEmpty {
                                Text(verbatim: trophy.detail)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.Text.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            if let game = trophy.game {
                                Text(verbatim: game.name)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.Text.tertiary)
                            }
                        }

                        StatsStrip(items: facts(of: trophy))

                        GameHelpSection(trophy: trophy)

                        TrophyTipSection(trophy: trophy)

                        if let progress = trophy.progress, !trophy.isEarned {
                            TrophyProgressCard(progress: progress, color: trophy.type.color)
                        }

                        FormSection(header: String(localized: "trophy.note.header")) {
                            FormTextField(
                                text: $note,
                                placeholder: String(localized: "trophy.note.placeholder"),
                                style: .rowMultiline(min: 2, max: 6)
                            )
                        }
                        .onAppear {
                            note = (try? app.store.note(gameId: trophy.gameId, trophyId: trophy.trophyId))?.text ?? ""
                        }
                        .onChange(of: note) { _, text in
                            try? app.store.setNote(text, gameId: trophy.gameId, trophyId: trophy.trophyId)
                        }

                        if let earnedAt = trophy.earnedAt {
                            StatusBanner(
                                String(localized: "trophy.earnedOn \(earnedAt.formatted(date: .long, time: .shortened))"),
                                status: .positive,
                                systemImage: "checkmark.seal.fill"
                            )
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.xl)
                }
            } else {
                EmptyState(icon: "trophy", title: String(localized: "trophy.missing"))
                    .screenPadding()
            }
        }
        .background(AppColors.Background.base)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func facts(of trophy: TrophyRecord) -> [StatsStrip.Item] {
        var items: [StatsStrip.Item] = [.init(value: trophy.type.title, title: String(localized: "trophy.fact.type"))]
        if let rate = trophy.earnedRate {
            items.append(.init(
                value: "\(rate.formatted(.number.precision(.fractionLength(1))))%",
                title: String(localized: "trophy.fact.rate")
            ))
        }
        if let rarity = trophy.rarity {
            items.append(.init(value: rarity.title, title: String(localized: "trophy.fact.rarity")))
        }
        return items
    }
}

/// The trophy's icon, large. The platinum, once earned, is a foil that follows the finger.
private struct TrophyHero: View {
    let trophy: TrophyRecord

    private let size: CGFloat = 180
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous) }

    var body: some View {
        let icon = RemotePhoto(key: "trophy-\(trophy.key)", url: trophy.iconURL)
            .frame(width: size, height: size)
            .clipShape(shape)
            .saturation(trophy.isEarned ? 1 : 0)
            .opacity(trophy.isEarned ? 1 : 0.7)
            .accessibilityLabel(Text(verbatim: trophy.name))

        if trophy.type == .platinum, trophy.isEarned {
            icon
                .holographic()
                .interactiveTilt(in: shape)
        } else {
            icon
        }
    }
}

/// A PS5 trophy that counts towards a target: "37 of 50".
private struct TrophyProgressCard: View {
    let progress: TrophyProgress
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("trophy.progress.title")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.Text.primary)
                Spacer()
                Text(verbatim: "\(progress.current)/\(progress.target)")
                    .font(AppTypography.bodyEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.Text.secondary)
            }
            LinearProgressBar(value: progress.fraction, color: color)
            if let updatedAt = progress.updatedAt {
                RelativeTime(updatedAt)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}
