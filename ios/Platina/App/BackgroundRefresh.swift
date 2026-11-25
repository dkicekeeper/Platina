import BackgroundTasks
import Foundation
import UserNotifications
import PlatinaStore

/// The sync while the app is away (docs/PLAN.md §9, stage 4): iOS wakes the app now and then
/// (`BGAppRefreshTask`, every few hours at best), it syncs, and a trophy earned since the last
/// look becomes a notification.
enum BackgroundRefresh {
    static let identifier = "dakacom.Platina.refresh"

    /// Asks iOS to wake the app in a couple of hours.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Whether the person said yes to notifications.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// One notification per new trophy (three at most, then a summary).
    static func notify(_ trophies: [TrophyRecord]) {
        let center = UNUserNotificationCenter.current()
        let shown = trophies.prefix(3)
        for trophy in shown {
            let content = UNMutableNotificationContent()
            content.title = trophy.type == .platinum
                ? String(localized: "notification.platinum.title")
                : String(localized: "notification.trophy.title")
            content.body = String(localized: "notification.trophy.body \(trophy.name) \(trophy.game?.name ?? "")")
            content.sound = .default
            content.threadIdentifier = trophy.gameId
            // A tap opens the game (AppDelegate).
            content.userInfo = ["gameId": trophy.gameId]
            center.add(UNNotificationRequest(identifier: "trophy-\(trophy.key)", content: content, trigger: nil))
        }
        if trophies.count > shown.count {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.trophy.title")
            content.body = String(localized: "notification.more \(trophies.count - shown.count)")
            center.add(UNNotificationRequest(identifier: "trophy-more-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }
}
