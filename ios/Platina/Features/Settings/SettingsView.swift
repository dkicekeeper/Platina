import SwiftUI
import DesignTokens
import DesignSupport
import DesignComponents
import PlatinaStore
import PSNKit

/// Settings, from the gear on the profile: the PSN account, trophy notifications from Plati's
/// server (`TrophyAlerts`), and whether hidden trophies and the walkthrough's spoilers show at
/// once or wait for a tap (`DisplaySettings`).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false
    @AppStorage(DisplaySettings.spoilersKey) private var showsSpoilers = false
    @State private var isConfirmingSignOut = false
    /// Turning trophy notifications on: Sony's sign-in once more, for the server's own code.
    @State private var isShowingAlertsSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                FormSection(header: String(localized: "profile.account.header")) {
                    UniversalRow(
                        String(localized: "profile.account.synced"),
                        icon: "arrow.triangle.2.circlepath",
                        value: app.sync.lastSyncedAt.map { Formatting.relativeTime($0) } ?? String(localized: "profile.account.never")
                    )
                    UniversalRow(
                        String(localized: "profile.account.syncNow"),
                        icon: "arrow.clockwise",
                        accessory: .action { Task { await app.sync.sync(force: true) } }
                    )
                    UniversalRow(
                        String(localized: "library.signOut"),
                        icon: "rectangle.portrait.and.arrow.right",
                        role: .destructive,
                        accessory: .action { isConfirmingSignOut = true }
                    )
                }
                if app.alerts.isAvailable {
                    alertsSection
                }
                FormSection(
                    header: String(localized: "settings.spoilers.header"),
                    footer: String(localized: "settings.spoilers.footer")
                ) {
                    UniversalRow(
                        String(localized: "settings.hiddenTrophies"),
                        icon: "eye",
                        accessory: .toggle($showsHiddenTrophies)
                    )
                    UniversalRow(
                        String(localized: "settings.spoilers"),
                        icon: "text.book.closed",
                        accessory: .toggle($showsSpoilers)
                    )
                }
                FormSection(header: String(localized: "settings.about.header")) {
                    UniversalRow(String(localized: "settings.version"), icon: "info.circle", value: Self.version)
                }
            }
            .screenPadding()
            .readableWidth()
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.Background.base)
        .navigationTitle(Text("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAlertsSignIn) {
            SonyLoginSheet { result in
                isShowingAlertsSignIn = false
                guard case .npsso(let token) = result else {
                    app.alerts.errorMessage = String(localized: "error.signInFailed")
                    return
                }
                Task { await app.alerts.turnOn(npsso: token, psn: app.client) }
            }
        }
        .confirmationDialog(
            Text("library.signOut.confirm"),
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button(String(localized: "library.signOut"), role: .destructive) {
                Task { await app.signOut() }
            }
        }
    }

    /// A push for every trophy, the app closed or not (docs/assistant.md §9). On asks Sony's
    /// sign-in once more: the server gets a code of its own, never the app's tokens.
    @ViewBuilder
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if let message = app.alerts.errorMessage {
                MessageBanner(message: message, type: .error)
            }
            FormSection(
                header: String(localized: "settings.alerts.header"),
                footer: app.alerts.state == .paused
                    ? String(localized: "settings.alerts.paused")
                    : String(localized: "settings.alerts.footer")
            ) {
                UniversalRow(
                    String(localized: "settings.alerts"),
                    icon: "bell.badge",
                    hint: app.alerts.isWorking ? String(localized: "settings.alerts.working") : nil,
                    accessory: .toggle(Binding(
                        get: { app.alerts.isOn || app.alerts.isWorking },
                        set: { isOn in
                            if isOn {
                                app.alerts.errorMessage = nil
                                isShowingAlertsSignIn = true
                            } else {
                                Task { await app.alerts.turnOff() }
                            }
                        }
                    ))
                )
            }
        }
    }

    /// "1.0 (18)": the version and the build, as TestFlight shows them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
