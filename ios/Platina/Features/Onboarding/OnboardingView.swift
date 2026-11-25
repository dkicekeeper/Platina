import SwiftUI
import DesignTokens
import DesignComponents

/// The first launch (docs/PLAN.md §9, stage 4): what the app does, then notifications, then
/// the sign-in.
struct OnboardingView: View {
    enum Page: Hashable, CaseIterable {
        case trophies, sessions, plati, notifications
    }

    let onFinish: () -> Void
    @State private var page: Page = .trophies

    var body: some View {
        OnboardingPager(
            pages: Page.allCases,
            selection: $page,
            skipTitle: String(localized: "onboarding.skip"),
            canSkip: { $0 != .notifications },
            onSkip: { page = .notifications }
        ) { page in
            switch page {
            case .trophies:
                OnboardingPage(
                    systemImage: "trophy.fill",
                    title: String(localized: "onboarding.trophies.title"),
                    message: String(localized: "onboarding.trophies.message")
                )
            case .sessions:
                OnboardingPage(
                    systemImage: "timer",
                    title: String(localized: "onboarding.sessions.title"),
                    message: String(localized: "onboarding.sessions.message")
                )
            case .plati:
                OnboardingPage(
                    systemImage: "sparkles",
                    title: String(localized: "onboarding.plati.title"),
                    message: String(localized: "onboarding.plati.message")
                ) {
                    ParticleCreature(mood: .happy, style: .hero, isInteractive: true)
                        .frame(width: 140, height: 140)
                        .accessibilityHidden(true)
                }
            case .notifications:
                OnboardingPage(
                    systemImage: "bell.badge.fill",
                    title: String(localized: "onboarding.notifications.title"),
                    message: String(localized: "onboarding.notifications.message")
                )
            }
        } actions: { page in
            switch page {
            case .notifications:
                VStack(spacing: AppSpacing.sm) {
                    DSButton(String(localized: "onboarding.notifications.allow"), systemImage: "bell", fullWidth: true) {
                        Task {
                            _ = await BackgroundRefresh.requestPermission()
                            onFinish()
                        }
                    }
                    DSButton(String(localized: "onboarding.notifications.later"), appearance: .flat, fullWidth: true) {
                        onFinish()
                    }
                }
            default:
                DSButton(String(localized: "onboarding.next"), fullWidth: true) {
                    withAnimation(AppAnimation.gentleSpring) {
                        self.page = next(after: page)
                    }
                }
            }
        }
        .background(AppColors.Background.base)
        // The screenshots' UI test relaunches an app that opened here instead of its demo.
        .accessibilityIdentifier("onboarding")
    }

    private func next(after page: Page) -> Page {
        let pages = Page.allCases
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else { return .notifications }
        return pages[index + 1]
    }
}
