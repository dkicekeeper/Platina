import SwiftUI
import DesignTokens
import DesignComponents

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarding.completed") private var isOnboardingDone = false

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                AppColors.Background.base.ignoresSafeArea()
            case .signedOut:
                if isOnboardingDone {
                    SignInView()
                        .transition(.opacity)
                } else {
                    OnboardingView { isOnboardingDone = true }
                        .transition(.opacity)
                }
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: model.phase)
    }
}

enum AppTab: Hashable {
    case path
    case games
    case plati
    case profile
}

/// The tabs (docs/PLAN.md §3): the path, the games, Plati, the profile.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = ScreenshotDemo.screen?.tab ?? .path

    var body: some View {
        @Bindable var app = app
        TabView(selection: $selection) {
            Tab(String(localized: "tab.path"), systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", value: AppTab.path) {
                PathView()
            }
            Tab(String(localized: "tab.games"), systemImage: "square.stack.fill", value: AppTab.games) {
                LibraryView()
            }
            Tab(value: AppTab.plati) {
                PlatiView()
            } label: {
                CreatureTabLabel(title: String(localized: "tab.plati"))
            }
            Tab(String(localized: "tab.profile"), systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        // A tab bar on iPhone, a sidebar on iPad and Mac.
        .tabViewStyle(.sidebarAdaptable)
        .liveSessionAccessory(isEnabled: app.sessions.current != nil) {
            if let session = app.sessions.current {
                LiveSessionBar(
                    startedAt: session.clockStart,
                    isPaused: session.isPaused,
                    detail: session.gameName,
                    accessibilityLabel: String(localized: "session.bar.accessibility \(session.gameName)")
                ) {
                    app.isShowingSession = true
                }
            }
        }
        .sheet(isPresented: $app.isShowingSession) {
            SessionView()
        }
        .sheet(item: $app.endedSession) { session in
            SessionSummaryView(session: session)
        }
        .task { await app.sync.sync() }
        .task(id: checkLoopKey) {
            await runChecks()
        }
        .onChange(of: scenePhase) { _, phase in
            app.isActive = phase == .active
            switch phase {
            case .active:
                Task { await app.sync.sync() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }

    /// The loop restarts when the session or the app's state changes.
    private var checkLoopKey: String {
        "\(app.sessions.current?.sessionId ?? "none")-\(scenePhase == .active)"
    }

    /// While a session runs and the app is open: a look for new trophies every couple of
    /// minutes (one light request when nothing changed). In the background iOS stops it; the
    /// next opening checks at once.
    private func runChecks() async {
        guard scenePhase == .active, app.sessions.current != nil else { return }
        while !Task.isCancelled, app.sessions.current != nil {
            if app.sessions.isCheckDue {
                await app.sessions.check()
            }
            try? await Task.sleep(for: .seconds(20))
        }
    }
}
