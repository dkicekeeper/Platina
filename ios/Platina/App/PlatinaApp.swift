import SwiftUI
import DesignTokens

@main
struct PlatinaApp: App {
    @State private var model = AppModel()

    init() {
        // Brand first, before any view renders (DesignKit README, "Using it in an app").
        DesignKitTheme.accent = PlatinaColors.accent
        DesignKitFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
