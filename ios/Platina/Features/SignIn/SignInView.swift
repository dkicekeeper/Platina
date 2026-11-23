import SwiftUI
import DesignTokens
import DesignComponents
import PSNKit

/// The first screen: Plati and the two ways to sign in to PSN.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @State private var isShowingSonyLogin = false
    @State private var isShowingNPSSO = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                ParticleCreature(mood: isSigningIn ? .thinking : .happy, style: .hero, isInteractive: true)
                    .frame(width: 220, height: 220)
                    .accessibilityHidden(true)

                VStack(spacing: AppSpacing.sm) {
                    Text("signIn.title")
                        .font(AppTypography.h1)
                        .foregroundStyle(AppColors.Text.primary)
                    Text("signIn.subtitle")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.Text.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: AppSpacing.md) {
                    DSButton(
                        String(localized: "signIn.psn"),
                        systemImage: "person.crop.circle.badge.checkmark",
                        fullWidth: true,
                        isLoading: isSigningIn
                    ) {
                        isShowingSonyLogin = true
                    }
                    DSButton(
                        String(localized: "signIn.npsso"),
                        appearance: .flat,
                        fullWidth: true,
                        isDisabled: isSigningIn
                    ) {
                        isShowingNPSSO = true
                    }
                }

                Text("signIn.privacy")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.Text.secondary)
                    .multilineTextAlignment(.center)
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppColors.Background.base)
        .overlay(alignment: .top) {
            if let message = errorMessage ?? model.signOutReason {
                MessageBanner(message: message, type: .error)
                    .screenPadding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        errorMessage = nil
                        model.signOutReason = nil
                    }
            }
        }
        .animation(AppAnimation.gentleSpring, value: errorMessage)
        .sheet(isPresented: $isShowingSonyLogin) {
            SonyLoginSheet { result in
                isShowingSonyLogin = false
                Task { await signIn(with: result) }
            }
        }
        .sheet(isPresented: $isShowingNPSSO) {
            NPSSOSheet { token in
                try await model.signIn(npsso: token)
            }
        }
    }

    private func signIn(with result: SonyLoginResult) async {
        errorMessage = nil
        guard case .npsso(let token) = result else {
            errorMessage = String(localized: "error.signInFailed")
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await model.signIn(npsso: token)
        } catch {
            errorMessage = error.userMessage
        }
    }
}
