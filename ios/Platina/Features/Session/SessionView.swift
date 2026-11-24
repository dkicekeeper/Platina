import SwiftUI
import SwiftData
import DesignTokens
import DesignSupport
import DesignComponents
import PSNKit
import PlatinaStore

/// The running session (docs/PLAN.md §3.5): the clock, the goals, the trophies it brought, a
/// note for next time; a check for new trophies; the end.
struct SessionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isConfirmingEnd = false
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            Group {
                if let session = app.sessions.current {
                    content(session)
                } else {
                    EmptyState(icon: "gamecontroller", title: String(localized: "session.none"))
                        .screenPadding()
                }
            }
            .background(AppColors.Background.base)
            .navigationTitle(Text("session.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "session.minimize")) { dismiss() }
                }
                if let session = app.sessions.current {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if session.isPaused {
                                app.sessions.resume()
                            } else {
                                app.sessions.pause()
                            }
                        } label: {
                            Label(
                                session.isPaused ? String(localized: "session.resume") : String(localized: "session.pause"),
                                systemImage: session.isPaused ? "play.fill" : "pause.fill"
                            )
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if let banner {
                    MessageBanner(message: banner, type: .success)
                        .screenPadding()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(4))
                            self.banner = nil
                        }
                }
            }
            .animation(AppAnimation.gentleSpring, value: banner)
            .confirmationDialog(Text("session.end.confirm"), isPresented: $isConfirmingEnd, titleVisibility: .visible) {
                Button(String(localized: "session.end")) {
                    Task { await app.endSession() }
                }
            }
            .onChange(of: app.celebration) { _, celebration in
                guard let celebration else { return }
                banner = celebration.isPlatinum
                    ? String(localized: "session.platinum")
                    : String(localized: "session.newTrophies \(celebration.trophyNames.joined(separator: ", "))")
                app.celebrationShown()
            }
        }
    }

    @ViewBuilder
    private func content(_ session: PlaySessionRecord) -> some View {
        let game = try? app.store.game(session.gameId)
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                SessionHeader(session: session, game: game)
                    .celebration(trigger: session.earnedTrophyIds.count)

                SessionTrophies(session: session, game: game)

                GoalsSection(session: session)

                SessionChapterCard(gameId: session.gameId)

                FormSection(header: String(localized: "session.note.header"), footer: String(localized: "session.note.footer")) {
                    FormTextField(
                        text: $note,
                        placeholder: String(localized: "session.note.placeholder"),
                        style: .rowMultiline(min: 2, max: 6)
                    )
                }

                VStack(spacing: AppSpacing.md) {
                    DSButton(
                        String(localized: "session.check"),
                        systemImage: "arrow.clockwise",
                        appearance: .secondary,
                        fullWidth: true,
                        isLoading: app.sessions.isChecking
                    ) {
                        Task {
                            let earned = await app.sessions.check()
                            if earned.isEmpty {
                                banner = String(localized: "session.check.nothing")
                            }
                        }
                    }
                    if let checked = app.sessions.lastCheckedAt {
                        Text("session.check.last \(Formatting.relativeTime(checked))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.Text.secondary)
                    }
                    DSButton(String(localized: "session.end"), systemImage: "flag.checkered", role: .destructive, fullWidth: true) {
                        isConfirmingEnd = true
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.lg)
        }
        .onAppear { note = session.note }
        .onChange(of: note) { _, text in
            app.sessions.setNote(text)
        }
    }
}

/// The game, the clock and the progress since the start.
private struct SessionHeader: View {
    let session: PlaySessionRecord
    let game: GameRecord?

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            RemotePhoto(key: "game-\(session.gameId)", url: game?.iconURL)
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: AppRadius.lg))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(verbatim: session.gameName)
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(AppColors.Text.primary)
                    .lineLimit(2)
                Group {
                    if session.isPaused {
                        Text(verbatim: Formatting.clockTime(session.elapsed(at: Date())))
                    } else {
                        RelativeTime(session.clockStart, style: .clock)
                    }
                }
                .font(AppTypography.numbers(AppTypography.h2))
                .foregroundStyle(session.isPaused ? AppColors.Text.secondary : AppColors.Text.primary)
                if session.isPaused {
                    Badge(String(localized: "session.paused"), systemImage: "pause.fill", color: AppColors.warning)
                }
                Text("session.progress \(session.startProgress) \(game?.progress ?? session.startProgress)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }
}

/// The trophies the session has brought so far.
private struct SessionTrophies: View {
    let session: PlaySessionRecord
    let game: GameRecord?

    var body: some View {
        let trophies = session.earnedTrophyIds.compactMap { id in game?.trophies.first { $0.trophyId == id } }
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(String(localized: "session.trophies.header"), systemImage: "trophy.fill")
            if trophies.isEmpty {
                Text("session.trophies.none")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.Text.secondary)
            } else {
                CardList(trophies, layout: .section) { (trophy: TrophyRecord) in
                    TrophyRow(trophy: trophy, isRevealed: true)
                }
            }
        }
    }
}

/// The session's goals: ticked when earned, or by hand; chosen from the game's trophies.
private struct GoalsSection: View {
    @Environment(AppModel.self) private var app
    let session: PlaySessionRecord
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false

    var body: some View {
        let goals = app.sessions.goalTrophies()
        FormSection(header: String(localized: "session.goals.header")) {
            ForEach(goals, id: \.key) { trophy in
                ChecklistRow(
                    trophy.isHidden && !trophy.isEarned && !showsHiddenTrophies ? String(localized: "trophy.hidden.title") : trophy.name,
                    isChecked: session.isGoalDone(trophy.trophyId),
                    tint: trophy.type.color,
                    accessorySystemImage: trophy.isEarned ? "trophy.fill" : nil,
                    accessoryLabel: trophy.isEarned ? String(localized: "session.goal.earned") : nil
                ) {
                    app.sessions.toggleGoal(trophy.trophyId)
                }
            }
            UniversalRow(
                goals.isEmpty ? String(localized: "session.goals.choose") : String(localized: "session.goals.change"),
                icon: "target",
                accessory: .navigation {
                    GoalPicker(gameId: session.gameId, initial: Set(session.goalTrophyIds))
                }
            )
        }
    }
}

/// The game's unearned trophies to pick goals from.
struct GoalPicker: View {
    let gameId: String
    @Environment(AppModel.self) private var app
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false
    @State private var selection: Set<Int>

    init(gameId: String, initial: Set<Int>) {
        self.gameId = gameId
        _selection = State(initialValue: initial)
    }

    var body: some View {
        let trophies = ((try? app.store.game(gameId))?.trophies ?? [])
            .filter { !$0.isEarned }
            .sorted(by: TrophySort.type.areInIncreasingOrder)
        SearchablePicker(
            trophies.map { trophy in
                SearchablePickerOption(
                    trophy.isHidden && !showsHiddenTrophies ? String(localized: "trophy.hidden.title") : trophy.name,
                    value: trophy.trophyId,
                    subtitle: trophy.isHidden && !showsHiddenTrophies ? trophy.type.title : trophy.detail,
                    systemImage: trophy.type.systemImage,
                    iconColor: trophy.type.color
                )
            },
            selection: $selection,
            prompt: String(localized: "session.goals.search")
        )
        .navigationTitle(Text("session.goals.header"))
        .onDisappear {
            let order = trophies.map(\.trophyId)
            app.sessions.setGoals(order.filter { selection.contains($0) })
        }
    }
}

/// What a finished session brought: time, trophies, progress, the note; Plati's summary when
/// it has written one.
struct SessionSummaryView: View {
    let session: PlaySessionRecord
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let game = try? app.store.game(session.gameId)
        let trophies = session.earnedTrophyIds.compactMap { id in game?.trophies.first { $0.trophyId == id } }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    VStack(spacing: AppSpacing.sm) {
                        HeroSymbol(systemImage: trophies.isEmpty ? "flag.checkered" : "trophy.fill", size: 120)
                        Text(verbatim: session.gameName)
                            .font(AppTypography.h3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    StatsStrip(items: [
                        .init(value: PlayTimeText.duration(session.elapsed(at: Date())), title: String(localized: "session.summary.time")),
                        .init(value: trophies.count.formatted(), title: String(localized: "session.summary.trophies")),
                        .init(
                            value: "\(session.startProgress)% → \(session.endProgress ?? session.startProgress)%",
                            title: String(localized: "session.summary.progress")
                        ),
                    ])

                    if let psn = session.psnSeconds, psn > 0 {
                        Text("session.summary.psnTime \(PlayTimeText.duration(psn))")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.Text.secondary)
                    }

                    if !trophies.isEmpty {
                        CardList(trophies, layout: .section) { (trophy: TrophyRecord) in
                            TrophyRow(trophy: trophy, isRevealed: true)
                        }
                    }

                    if let summary = session.summary {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            SectionHeader(String(localized: "session.summary.plati"), systemImage: "sparkles")
                            ArticleBody(Self.blocks(summary: summary, nextSteps: session.nextSteps))
                        }
                    }

                    if !session.note.isEmpty {
                        StatusBanner(session.note, status: .neutral, systemImage: "bookmark.fill")
                    }
                }
                .screenPadding()
                .padding(.vertical, AppSpacing.lg)
            }
            .background(AppColors.Background.base)
            .navigationTitle(Text("session.summary.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "session.summary.done")) { dismiss() }
                }
            }
        }
    }

    private static func blocks(summary: String, nextSteps: String?) -> [ArticleBody.Block] {
        var blocks: [ArticleBody.Block] = [.paragraph(summary)]
        if let nextSteps, !nextSteps.isEmpty {
            blocks.append(.note(nextSteps))
        }
        return blocks
    }
}
