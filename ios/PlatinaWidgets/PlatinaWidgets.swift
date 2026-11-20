import SwiftUI
import WidgetKit
import DesignTokens

/// Platina's widget extension: the session's Live Activity (stage 2) and the home screen
/// widgets (stage 4).
@main
struct PlatinaWidgets: WidgetBundle {
    init() {
        DesignKitTheme.accent = WidgetColors.accent
        DesignKitFonts.registerIfNeeded()
    }

    var body: some Widget {
        SessionLiveActivityWidget()
        PlatinumProgressWidget()
        LatestTrophyWidget()
    }
}

enum WidgetColors {
    /// The app's accent, #3573BA (PlatinaColors.accent in the app).
    static let accent = Color(red: 53 / 255, green: 115 / 255, blue: 186 / 255)
}
