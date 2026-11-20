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
                LibraryView(app: model)
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.gentleSpring, value: model.phase)
    }
}
