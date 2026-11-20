import SwiftUI
import WebKit
import DesignTokens
import PSNKit

/// What the Sony sign-in page ended with.
enum SonyLoginResult: Equatable {
    /// Sony redirected back with an authorization code: the usual way.
    case code(String)
    /// No redirect, but the page left the `npsso` cookie: exchange it instead.
    case npsso(String)
    /// Sony redirected back with an error.
    case failed
}

/// Sony's own sign-in page in a web view. The person types the password into Sony's form; the
/// app only sees where the page redirects to at the end (docs/PLAN.md §2).
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
        // Nothing of Sony's session stays in the app after the sheet closes: the tokens do.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: PSNAuth.authorizeURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var isLoading: Binding<Bool>
        private let onFinish: (SonyLoginResult) -> Void
        private var isFinished = false

        init(isLoading: Binding<Bool>, onFinish: @escaping (SonyLoginResult) -> Void) {
            self.isLoading = isLoading
            self.onFinish = onFinish
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, PSNAuth.isRedirect(url) else {
                return .allow
            }
            finish(with: url)
            return .cancel
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
            // The sign-in ended on a page instead of the redirect (an account page after
            // two-step verification): the npsso cookie is enough to finish.
            Task { await finishWithCookieIfPresent(webView) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            isLoading.wrappedValue = false
            // Some WebKit versions fail the redirect to the app's scheme instead of asking first.
            let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            if let failingURL, let url = URL(string: failingURL), PSNAuth.isRedirect(url) {
                finish(with: url)
            }
        }

        private func finish(with redirect: URL) {
            guard !isFinished else { return }
            isFinished = true
            if let code = PSNAuth.authorizationCode(fromRedirect: redirect) {
                onFinish(.code(code))
            } else {
                onFinish(.failed)
            }
        }

        private func finishWithCookieIfPresent(_ webView: WKWebView) async {
            guard !isFinished else { return }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard !isFinished,
                  let cookie = cookies.first(where: { $0.name == "npsso" && $0.domain.contains("sony.com") }),
                  let token = PSNAuth.normalizedNPSSO(cookie.value) else { return }
            isFinished = true
            onFinish(.npsso(token))
        }
    }
}
