import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PSNKit

@Suite("Sign-in")
struct AuthTests {
    @Test("The store's sign-in ends at its session service or at the store, not on the way there")
    func storeSignInFinished() throws {
        #expect(PSNAuth.storeSignInURL.host == "web.np.playstation.com")
        let finished = [
            "https://web.np.playstation.com/api/session/v1/session?redirect_uri=https%3A%2F%2Fstore.playstation.com%2F&code=v3.abc",
            "https://store.playstation.com/en-us/pages/latest",
        ]
        for string in finished {
            #expect(PSNAuth.isStoreSignInFinished(try #require(URL(string: string))))
        }
        let onTheWay = [
            PSNAuth.storeSignInURL.absoluteString,
            "https://ca.account.sony.com/api/authz/v3/oauth/authorize?client_id=e4a62faf-4b87-4fea-8565-caaabb3ac918",
            "https://my.account.sony.com/sonyacct/signin/?client_id=e4a62faf-4b87-4fea-8565-caaabb3ac918",
        ]
        for string in onTheWay {
            #expect(!PSNAuth.isStoreSignInFinished(try #require(URL(string: string))))
        }
    }

    @Test("The authorize page asks for an offline code for the PlayStation App's client")
    func authorizeURL() throws {
        let components = try #require(URLComponents(url: PSNAuth.authorizeURL, resolvingAgainstBaseURL: false))
        #expect(components.host == "ca.account.sony.com")
        #expect(components.path == "/api/authz/v3/oauth/authorize")
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        #expect(query["access_type"] == "offline")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "09515159-7237-4370-9b40-3806e67c0891")
        #expect(query["redirect_uri"] == "com.scee.psxandroid.scecompcall://redirect")
        #expect(query["scope"] == "psn:mobile.v2.core psn:clientapp")
    }

    @Test("The code from Sony's redirect")
    func redirectCode() throws {
        let url = try #require(URL(string: "com.scee.psxandroid.scecompcall://redirect/?code=v3.AbC123&cid=4f2e"))
        #expect(PSNAuth.isRedirect(url))
        #expect(PSNAuth.authorizationCode(fromRedirect: url) == "v3.AbC123")

        let failed = try #require(URL(string: "com.scee.psxandroid.scecompcall://redirect/?error=login_required&cid=1"))
        #expect(PSNAuth.authorizationCode(fromRedirect: failed) == nil)

        let other = try #require(URL(string: "https://www.playstation.com/"))
        #expect(!PSNAuth.isRedirect(other))
    }

    @Test("A pasted NPSSO token, bare or as the ssocookie answer")
    func npsso() {
        let token = String(repeating: "aB3", count: 21) + "x"
        #expect(PSNAuth.normalizedNPSSO("  \(token)\n") == token)
        #expect(PSNAuth.normalizedNPSSO("{\"npsso\":\"\(token)\"}") == token)
        #expect(PSNAuth.normalizedNPSSO("short") == nil)
        #expect(PSNAuth.normalizedNPSSO("not a token at all, but long enough to pass the length") == nil)
    }

    @Test("Form fields are encoded as URLSearchParams does")
    func formEncoding() {
        #expect(FormEncoding.encode([("scope", "psn:mobile.v2.core psn:clientapp")])
            == "scope=psn%3Amobile.v2.core+psn%3Aclientapp")
        #expect(FormEncoding.encode([("redirect_uri", "com.scee.psxandroid.scecompcall://redirect")])
            == "redirect_uri=com.scee.psxandroid.scecompcall%3A%2F%2Fredirect")
    }

    @Test("NPSSO → code → tokens")
    func npssoExchange() async throws {
        let transport = MockTransport { request in
            if request.url?.path == "/api/authz/v3/oauth/authorize" {
                #expect(request.value(forHTTPHeaderField: "Cookie") == "npsso=TOKEN")
                return .init(status: 302, headers: ["Location": "com.scee.psxandroid.scecompcall://redirect/?code=v3.CODE&cid=1"])
            }
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
            #expect(request.formFields["code"] == "v3.CODE")
            #expect(request.formFields["grant_type"] == "authorization_code")
            #expect(request.formFields["token_format"] == "jwt")
            return tokenResponse(access: "A", refresh: "R")
        }
        let authenticator = PSNAuthenticator(transport: transport, now: { fixedNow })
        let tokens = try await authenticator.tokens(fromNPSSO: "TOKEN")
        #expect(tokens.accessToken == "A")
        #expect(tokens.refreshToken == "R")
        #expect(tokens.accessTokenExpiresAt == fixedNow.addingTimeInterval(3599))
        #expect(tokens.refreshTokenExpiresAt == fixedNow.addingTimeInterval(5_183_999))
    }

    @Test("A rejected NPSSO")
    func invalidNPSSO() async {
        let transport = MockTransport { _ in
            .init(status: 302, headers: ["Location": "com.scee.psxandroid.scecompcall://redirect/?error=login_required"])
        }
        let authenticator = PSNAuthenticator(transport: transport)
        await #expect(throws: PSNError.invalidNPSSO) {
            try await authenticator.tokens(fromNPSSO: "OLD")
        }
    }

    @Test("A refresh token Sony no longer accepts")
    func expiredRefresh() async {
        let transport = MockTransport { _ in
            .init(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"Invalid refresh token"}"#.utf8))
        }
        let authenticator = PSNAuthenticator(transport: transport)
        await #expect(throws: PSNError.sessionExpired) {
            try await authenticator.refresh("R")
        }
    }
}
