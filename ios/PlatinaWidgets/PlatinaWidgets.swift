import SwiftUI
import WidgetKit
import DesignTokens
import PlatinaShared

/// Platina's widget extension: the session's Live Activity (stage 2) and the home screen
/// widgets (stage 4).
@main
struct PlatinaWidgets: WidgetBundle {
    init() {
        DesignKitTheme.accent = PlatinaPalette.accent
        DesignKitFonts.registerIfNeeded()
    }

    var body: some Widget {
        SessionLiveActivityWidget()
        PlatinumProgressWidget()
        LatestTrophyWidget()
    }
}
