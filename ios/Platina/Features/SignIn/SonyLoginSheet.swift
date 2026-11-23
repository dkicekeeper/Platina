import SwiftUI
import UIKit
import WebKit
import DesignTokens
import PSNKit

/// What the sign-in window ended with.
enum SonyLoginResult: Equatable {
    /// The person signed in: Sony's session token, to exchange for the app's tokens.
    case npsso(String)
    /// The sign-in ended without a token.
    case failed
}

/// The PlayStation Store's sign-in in a web view (docs/PLAN.md §2). The page of the PlayStation
/// App's client, which the app's tokens belong to, does not load for some people ("the connection
/// to the server timed out"), the store's does. When the store's sign-in is over, the app takes
/// Sony's session token (`npsso`) the way a person would by hand, and exchanges it for its own.
/// The person types the password into Sony's form; the app sees only the token.
struct SonyLoginSheet: View {
    let onFinish: (SonyLoginResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            SonyLoginWebView(isLoading: $isLoading, onFinish: onFinish)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
                .navigationTitle(Text("signIn.sheet.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel"), role: .cancel) { dismiss() }
                    }
                }
        }
    }
}

private struct SonyLoginWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    let onFinish: (SonyLoginResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onFinish: onFinish)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Nothing of Sony's session stays in the app after the window closes: the tokens do.
        configuration.websiteDataStore = .nonPersistent()
        // Safari's own user agent: a web view's lacks "Version/… Safari/…", and sign-in pages
        // treat a browser they do not know with suspicion.
        let version = UIDevice.current.systemVersion
        configuration.applicationNameForUserAgent = "Version/\(version) Mobile/15E148 Safari/604.1"
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: PSNAuth.storeSignInURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private enum Stage {
            case signingIn
            /// Signed in; the token page is loading.
            case readingToken
            case finished
        }

        private var isLoading: Binding<Bool>
        private let onFinish: (SonyLoginResult) -> Void
        private var stage = Stage.signingIn
        /// The token page's load: the cancelled redirect before it reports a failure of its own.
        private var tokenNavigation: WKNavigation?

        init(isLoading: Binding<Bool>, onFinish: @escaping (SonyLoginResult) -> Void) {
            self.isLoading = isLoading
            self.onFinish = onFinish
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard stage == .signingIn, let url = navigationAction.request.url, PSNAuth.isStoreSignInFinished(url) else {
                return .allow
            }
            // Signed in: the store itself is not needed, Sony's session is. The token is taken
            // once this redirect is cancelled.
            stage = .readingToken
            isLoading.wrappedValue = true
            Task { await self.takeToken(from: webView) }
            return .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            switch stage {
            case .signingIn:
                isLoading.wrappedValue = false
            case .readingToken where navigation === tokenNavigation:
                Task { await self.readTokenPage(webView) }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            switch stage {
            case .signingIn:
                isLoading.wrappedValue = false
            case .readingToken where navigation === tokenNavigation:
                finish(.failed)
            default:
                break
            }
        }

        /// The token from Sony's cookie; failing that, from the token page, as a person reads it.
        private func takeToken(from webView: WKWebView) async {
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            if let cookie = cookies.first(where: { $0.name == "npsso" && $0.domain.contains("sony.com") }),
               let token = PSNAuth.normalizedNPSSO(cookie.value) {
                finish(.npsso(token))
                return
            }
            tokenNavigation = webView.load(URLRequest(url: PSNAuth.ssoCookieURL))
        }

        private func readTokenPage(_ webView: WKWebView) async {
            let text = try? await webView.evaluateJavaScript("document.body.innerText") as? String
            if let text, let token = PSNAuth.normalizedNPSSO(text) {
                finish(.npsso(token))
            } else {
                finish(.failed)
            }
        }

        private func finish(_ result: SonyLoginResult) {
            guard stage != .finished else { return }
            stage = .finished
            onFinish(result)
        }
    }
}
