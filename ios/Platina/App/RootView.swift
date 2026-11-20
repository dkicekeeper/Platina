import SwiftUI
import DesignTokens

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                AppColors.Background.base.ignoresSafeArea()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: model.phase)
    }
}

enum AppTab: Hashable {
    case games
    case profile
}

/// The tabs (docs/PLAN.md §3). "The path" and Plati come with stages 2 and 3.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .games

    var body: some View {
        TabView(selection: $selection) {
            Tab(String(localized: "tab.games"), systemImage: "square.stack.fill", value: AppTab.games) {
                LibraryView()
            }
            Tab(String(localized: "tab.profile"), systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .task { await app.sync.sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.sync.sync() }
            }
        }
    }
}
