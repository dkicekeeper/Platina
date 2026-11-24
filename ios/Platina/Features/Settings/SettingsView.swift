import SwiftUI
import DesignTokens
import DesignSupport
import DesignComponents
import PlatinaStore

/// Settings, from the gear on the profile: the PSN account, and whether hidden trophies and
/// the walkthrough's spoilers show at once or wait for a tap (`DisplaySettings`).
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(DisplaySettings.hiddenTrophiesKey) private var showsHiddenTrophies = false
    @AppStorage(DisplaySettings.spoilersKey) private var showsSpoilers = false
    @State private var isConfirmingSignOut = false

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

    /// "1.0 (18)": the version and the build, as TestFlight shows them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
