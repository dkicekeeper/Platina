import Foundation
import UIKit
import UserNotifications
import os
import PSNKit
import PlatinaAssistant

/// Trophy notifications from Plati's server (docs/assistant.md §9): a push for every trophy, the
/// app open or not. The person turns them on in Settings; the app asks iOS for notifications and
/// a device token, then Sony for a second authorization code from the sign-in's NPSSO, and hands
/// only that code to the server, which exchanges it for tokens of its own. The phone's tokens
/// never leave the phone. While they are on, the background refresh posts no notifications of its
/// own (no duplicates). When Sony stops accepting the server's grant (about every two months) the
/// server sends one "sign in again" and stops; the next sign-in turns them back on.
@MainActor
@Observable
final class TrophyAlerts {
    static let shared = TrophyAlerts()

    enum State: String {
        case off, on
        /// The server stopped (Sony refused its grant): a sign-in turns them back on.
        case paused
    }

    /// A game a notification asked to open.
    struct OpenRequest: Equatable {
        let gameId: String
        let id = UUID()
        let at = Date()

        /// A tap that just happened, not one left from before a sign-out.
        var isFresh: Bool { Date().timeIntervalSince(at) < 60 }
    }

    private(set) var state: State
    private(set) var isWorking = false
    /// Why turning on failed, for Settings.
    var errorMessage: String?
    /// Set by a tap on a notification: the tabs and the library open the game.
    var openRequest: OpenRequest?

    var isOn: Bool { state == .on }
    /// The server is set up and this device signs its requests (App Attest).
    var isAvailable: Bool { client != nil }

    private static let stateKey = "trophyAlerts.state"
    private static let tokenKey = "trophyAlerts.deviceToken"
    private static let log = Logger(subsystem: "dakacom.Platina", category: "Plati")

    @ObservationIgnored private var client: TrophyAlertsClient?
    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private var tokenWaiters: [CheckedContinuation<String?, Never>] = []

    private init() {
        state = State(rawValue: UserDefaults.standard.string(forKey: Self.stateKey) ?? "") ?? .off
        deviceToken = UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    /// Xcode's builds get pushes from APNs' sandbox; TestFlight and the App Store from production.
    static var environment: TrophyAlertsClient.Environment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    /// The server's client (nil: no server, or no App Attest here). While the notifications are
    /// on, iOS is asked for the device token on every launch, as Apple advises: the answer checks
    /// in with the server.
    func configure(client: TrophyAlertsClient?) {
        self.client = client
        if client != nil, isOn {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Turns the notifications on with the NPSSO of a sign-in that just happened.
    func turnOn(npsso: String, psn: PSNClient) async {
        guard let client, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        guard await BackgroundRefresh.requestPermission() else {
            errorMessage = String(localized: "alerts.error.permission")
            return
        }
        guard let token = await requestDeviceToken() else {
            errorMessage = String(localized: "alerts.error.push")
            return
        }
        do {
            let code = try await psn.serverAuthorizationCode(npsso: npsso)
            try await client.subscribe(code: code, pushToken: token, environment: Self.environment, language: AppLanguage.code)
            setState(.on)
        } catch {
            Self.log.error("Alerts: \(String(describing: error), privacy: .public)")
            errorMessage = Self.message(for: error)
        }
    }

    /// Turns them off: the server forgets its grant and everything else.
    func turnOff() async {
        guard state != .off else { return }
        setState(.off)
        errorMessage = nil
        do {
            try await client?.unsubscribe()
        } catch {
            Self.log.error("Alerts off: \(String(describing: error), privacy: .public)")
        }
    }

    /// A new sign-in: notifications that were on or paused get the server a new grant.
    func signedIn(npsso: String, psn: PSNClient) async {
        guard state != .off else { return }
        await turnOn(npsso: npsso, psn: psn)
    }

    // MARK: The device token

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        resumeWaiters(with: token)
        if isOn, let client {
            Task {
                // The server stopped watching (Sony refused its grant): say so in Settings.
                if let watching = try? await client.updateToken(token, environment: Self.environment), !watching {
                    setState(.paused)
                }
            }
        }
    }

    func didFailToRegister(_ error: any Error) {
        Self.log.error("Push registration: \(String(describing: error), privacy: .public)")
        resumeWaiters(with: nil)
    }

    /// A tap on a notification (the server's or the background refresh's): its game.
    func open(gameId: String?) {
        guard let gameId, !gameId.isEmpty else { return }
        openRequest = OpenRequest(gameId: gameId)
    }

    private func requestDeviceToken() async -> String? {
        await withCheckedContinuation { continuation in
            tokenWaiters.append(continuation)
            UIApplication.shared.registerForRemoteNotifications()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                self?.resumeWaiters(with: nil)
            }
        }
    }

    private func resumeWaiters(with token: String?) {
        let waiters = tokenWaiters
        tokenWaiters = []
        for waiter in waiters {
            waiter.resume(returning: token)
        }
    }

    private func setState(_ new: State) {
        state = new
        UserDefaults.standard.set(new.rawValue, forKey: Self.stateKey)
    }

    private static func message(for error: any Error) -> String {
        if let error = error as? AssistantServerError {
            if error == .invalidRequest(reason: "code") { return String(localized: "alerts.error.code") }
            if error == .disabled { return String(localized: "alerts.error.unavailable") }
            return String(localized: "alerts.error.generic")
        }
        if let error = error as? PSNError { return error.userMessage }
        return String(localized: "alerts.error.generic")
    }
}

/// The app's delegate: the device token for trophy notifications, and a tap on a notification
/// opens its game.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        TrophyAlerts.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        TrophyAlerts.shared.didFailToRegister(error)
    }

    /// With the app open a trophy still shows: a banner over whatever is on screen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let gameId = response.notification.request.content.userInfo["gameId"] as? String
        await MainActor.run {
            TrophyAlerts.shared.open(gameId: gameId)
        }
    }
}
