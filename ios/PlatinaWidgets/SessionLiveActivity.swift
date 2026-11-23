import ActivityKit
import SwiftUI
import WidgetKit
import DesignTokens
import PlatinaShared

/// The session's Live Activity: the lock screen and the Dynamic Island. Every text comes from
/// the app in its language; the clock runs by itself.
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(AppSpacing.lg)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(verbatim: context.attributes.gameName)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(AppColors.accent)
                    }
                    .font(AppTypography.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionClock(state: context.state)
                        .font(AppTypography.numbers(AppTypography.bodyEmphasis))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        ProgressView(value: Double(context.state.progress), total: 100)
                            .tint(AppColors.accent)
                        if let step = context.state.step {
                            StepRow(gameId: context.attributes.gameId, step: step)
                        } else {
                            HStack {
                                Text(verbatim: context.state.statusText ?? context.state.trophiesText)
                                Spacer(minLength: 0)
                                if let goals = context.state.goalsText {
                                    Text(verbatim: goals)
                                }
                            }
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.Text.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(AppColors.accent)
            } compactTrailing: {
                SessionClock(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(AppColors.accent)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: SessionActivityAttributes
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: attributes.gameName)
                    .font(AppTypography.bodyEmphasis)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                SessionClock(state: state)
                    .font(AppTypography.numbers(AppTypography.h4))
            }
            ProgressView(value: Double(state.progress), total: 100) {
                EmptyView()
            } currentValueLabel: {
                Text(verbatim: "\(state.progress)%")
            }
            .tint(AppColors.accent)
            HStack {
                Text(verbatim: state.statusText ?? state.trophiesText)
                Spacer(minLength: AppSpacing.sm)
                if let goals = state.goalsText {
                    Text(verbatim: goals)
                }
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.Text.secondary)
            if let step = state.step {
                StepRow(gameId: attributes.gameId, step: step)
            } else if let next = state.nextGoal {
                Label {
                    Text(verbatim: next).lineLimit(1)
                } icon: {
                    Image(systemName: "target")
                }
                .font(AppTypography.caption)
            }
        }
    }
}

/// The walkthrough's step to do now, with a ✓ that ticks it without opening the app.
private struct StepRow: View {
    let gameId: String
    let step: SessionActivityAttributes.ContentState.Step

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: step.chapterText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.Text.secondary)
                    .lineLimit(1)
                Text(verbatim: step.text)
                    .font(AppTypography.caption)
                    .lineLimit(2)
            }
            Spacer(minLength: AppSpacing.sm)
            Button(intent: CompleteStepIntent(gameId: gameId, chapterId: step.chapterId, stepId: step.stepId)) {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: step.doneLabel))
        }
    }
}

/// The time played: running, or frozen on a pause.
private struct SessionClock: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(Duration.seconds(paused), format: .time(pattern: .hourMinuteSecond))
                .foregroundStyle(AppColors.Text.secondary)
        } else {
            Text(timerInterval: state.clockStart...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        }
    }
}
