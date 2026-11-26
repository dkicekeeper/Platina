import SwiftUI
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaAssistant
import PlatinaStore

/// The guide on a game's screen (docs/domains/screens.md §3.3): difficulty, hours, playthroughs,
/// missables, the road map by steps and the sources. Built by Plati's server from Stratege.ru
/// and the web; the person starts the build (it costs a model call), or Plati does when it needs
/// the guide.
struct GuideSection: View {
    let game: GameRecord
    @Environment(AppModel.self) private var app
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let guides = app.assistant.guides
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "guide.header"), systemImage: "map")
            if let guide = guides.guide(for: game.id) {
                content(guide)
            } else {
                switch guides.state(for: game.id) {
                case .building(let step):
                    building(step)
                case .failed:
                    StatusBanner(String(localized: "guide.failed"), status: .warning) {
                        Task { await guides.build(gameId: game.id) }
                    }
                case .idle:
                    if guides.isAvailable, PlatiAvailability.current.canWrite {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("guide.empty")
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.Text.secondary)
                            DSButton(String(localized: "guide.build"), systemImage: "sparkles", appearance: .secondary, fullWidth: true) {
                                Task { await guides.build(gameId: game.id) }
                            }
                        }
                        .padding(AppSpacing.lg)
                        .cardStyle()
                    } else {
                        StatusBanner(PlatiAvailability.current.message, status: .neutral, systemImage: "wrench.and.screwdriver")
                    }
                }
            }
        }
        .task { await guides.fetchCached(gameId: game.id) }
    }

    private func building(_ step: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ParticleCreature(mood: .working(progress: progress(of: step)), style: .compact)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            Text(stepText(step))
                .font(AppTypography.bodySmall)
                .thinkingShimmer()
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    @ViewBuilder
    private func content(_ guide: Guide) -> some View {
        let summary = guide.summary
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            StatsStrip(items: summaryItems(guide))
            if let overview = summary.overview, !overview.isEmpty {
                ExpandableText(overview, lineLimit: 4, font: AppTypography.bodySmall)
            }
            badges(summary)
        }
        .padding(AppSpacing.lg)
        .cardStyle()

        if !guide.missable.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                StatusBanner(String(localized: "guide.missable.banner \(guide.missable.count)"), status: .warning, systemImage: "exclamationmark.triangle.fill")
                ForEach(guide.missable, id: \.trophyId) { missable in
                    let trophy = game.trophies.first { $0.trophyId == missable.trophyId }
                    ChecklistRow(
                        trophy.map { $0.isHidden && !$0.isEarned && !showsHiddenTrophies ? String(localized: "trophy.hidden.title") : $0.name } ?? "#\(missable.trophyId)",
                        isChecked: trophy?.isEarned ?? false,
                        tint: trophy?.type.color ?? AppColors.Status.warning,
                        verticalPadding: AppSpacing.xs
                    ) {}
                    .disabled(true)
                    Text(verbatim: missable.note)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.Text.secondary)
                        .padding(.leading, AppSpacing.xxl + AppSpacing.sm)
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }

        if !guide.steps.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "guide.roadmap"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    RoadmapStepCard(step: step, number: index + 1, game: game)
                }
            }
        }

        if !guide.sources.isEmpty {
            FormSection(header: String(localized: "guide.sources")) {
                ForEach(guide.sources) { source in
                    UniversalRow(source.title, icon: "link", accessory: .action {
                        if let url = URL(string: source.url) { openURL(url) }
                    })
                }
            }
        }

        DSButton(String(localized: "guide.refresh"), systemImage: "arrow.clockwise", appearance: .flat, size: .small) {
            Task { await app.assistant.guides.build(gameId: game.id, refresh: true) }
        }
    }

    private func summaryItems(_ guide: Guide) -> [StatsStrip.Item] {
        let summary = guide.summary
        var items: [StatsStrip.Item] = []
        if let difficulty = summary.difficulty {
            items.append(.init(value: "\(difficulty)/10", title: String(localized: "guide.difficulty")))
        }
        if let hours = hoursText(summary) {
            items.append(.init(value: hours, title: String(localized: "guide.hours")))
        }
        if let playthroughs = summary.playthroughs {
            items.append(.init(value: playthroughs.formatted(), title: String(localized: "guide.playthroughs")))
        }
        if let missable = summary.missableTrophies {
            items.append(.init(value: missable.formatted(), title: String(localized: "guide.missable")))
        }
        return items
    }

    private func hoursText(_ summary: Guide.Summary) -> String? {
        switch (summary.hoursMin, summary.hoursMax) {
        case let (min?, max?) where max > min: "\(Int(min))–\(Int(max))"
        case let (min?, _): "\(Int(min))+"
        case let (nil, max?): "≤\(Int(max))"
        default: nil
        }
    }

    @ViewBuilder
    private func badges(_ summary: Guide.Summary) -> some View {
        let online = summary.onlineTrophies ?? 0
        let glitched = summary.glitchedTrophies ?? 0
        if online > 0 || glitched > 0 || summary.difficultyAffects == true {
            FlowLayout(spacing: AppSpacing.sm) {
                if online > 0 {
                    Badge(String(localized: "guide.online \(online)"), systemImage: "wifi", color: AppColors.Status.info)
                }
                if glitched > 0 {
                    Badge(String(localized: "guide.glitched \(glitched)"), systemImage: "ladybug", color: AppColors.Status.warning)
                }
                if summary.difficultyAffects == true {
                    Badge(String(localized: "guide.difficultyAffects"), systemImage: "dial.high", color: AppColors.Status.neutral)
                }
            }
        }
    }

    private func progress(of step: String) -> Double {
        switch step {
        case "stratege": 0.25
        case "search": 0.5
        case "writing": 0.8
        default: 0.1
        }
    }

    private func stepText(_ step: String) -> String {
        switch step {
        case "stratege": String(localized: "guide.step.stratege")
        case "search": String(localized: "guide.step.search")
        case "writing": String(localized: "guide.step.writing")
        default: String(localized: "guide.step.start")
        }
    }
}

/// A step of the road map: its title, how many of its trophies are earned, its text.
private struct RoadmapStepCard: View {
    let step: Guide.Step
    let number: Int
    let game: GameRecord

    var body: some View {
        let trophies = game.trophies.filter { step.trophyIds.contains($0.trophyId) }
        let earned = trophies.filter(\.isEarned).count
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            ChecklistSummaryRow(
                title: step.title,
                checked: earned,
                total: trophies.count,
                progressText: trophies.isEmpty ? nil : "\(earned)/\(trophies.count)",
                emptyText: String(localized: "guide.step.noTrophies")
            )
            ArticleBody(ArticleBody.Block.parse(markdown: step.text))
        }
        .padding(AppSpacing.lg)
        .cardStyle()
        .completionMoment(isComplete: !trophies.isEmpty && earned == trophies.count, in: RoundedRectangle(cornerRadius: AppRadius.xl))
    }
}

/// A trophy's tip from the guide, with its sources, on the trophy's screen.
struct TrophyTipSection: View {
    let trophy: TrophyRecord
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let guide = app.assistant.guides.guide(for: trophy.gameId)
        if let guide {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let missable = guide.missable(for: trophy.trophyId), !trophy.isEarned {
                    StatusBanner(String(localized: "trophy.missable \(missable.note)"), status: .warning, systemImage: "exclamationmark.triangle.fill")
                }
                if let tip = guide.tip(for: trophy.trophyId) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        SectionHeader(String(localized: "trophy.tip.header"), systemImage: "lightbulb")
                        ArticleBody(ArticleBody.Block.parse(markdown: tip.text))
                        let sources = guide.sources(of: tip)
                        if !sources.isEmpty {
                            FlowLayout(spacing: AppSpacing.sm) {
                                ForEach(sources) { source in
                                    Button {
                                        if let url = URL(string: source.url) { openURL(url) }
                                    } label: {
                                        Badge(source.title, systemImage: "link")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .cardStyle()
                }
                if let step = guide.steps.first(where: { $0.trophyIds.contains(trophy.trophyId) }) {
                    RecommendationBox(text: String(localized: "trophy.tip.step \(step.title)"), color: AppColors.accent, icon: "map")
                }
            }
        }
    }
}
