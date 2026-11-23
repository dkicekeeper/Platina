import SwiftUI
import AuthenticationServices
import DesignTokens
import DesignComponents
import PSNKit

/// The first screen: Plati and the two ways to sign in to PSN.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
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
                        Task { await signInWithSony() }
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
        .sheet(isPresented: $isShowingNPSSO) {
            NPSSOSheet { token in
                try await model.signIn(npsso: token)
            }
        }
    }

    /// Sony's sign-in page in Safari's own sheet, not in a web view of the app: Sony's bot
    /// protection stalls its page inside a web view ("the connection timed out"), Safari it lets
    /// through. Passwords and passkeys come from the Keychain, the app sees only the redirect
    /// with the code. The session is ephemeral: Safari keeps nothing of it, and iOS asks nothing
    /// before it opens. The redirect's scheme is the PlayStation App's; the sheet catches it
    /// itself, the app does not register it.
    private func signInWithSony() async {
        errorMessage = nil
        let redirect: URL
        do {
            redirect = try await webAuthenticationSession.authenticate(
                using: PSNAuth.authorizeURL,
                callback: .customScheme(PSNAuth.redirectScheme),
                preferredBrowserSession: .ephemeral,
                additionalHeaderFields: [:]
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            errorMessage = String(localized: "error.signInFailed")
            return
        }
        guard let code = PSNAuth.authorizationCode(fromRedirect: redirect) else {
            errorMessage = String(localized: "error.signInFailed")
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await model.signIn(authorizationCode: code)
        } catch {
            errorMessage = error.userMessage
        }
    }
}
