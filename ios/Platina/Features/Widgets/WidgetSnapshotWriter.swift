import Foundation
import WidgetKit
import PSNKit
import PlatinaCore
import PlatinaShared
import PlatinaStore

/// Writes what the home screen widgets show (docs/PLAN.md §9, stage 4) after every sync and
/// session, and asks WidgetKit to redraw them.
@MainActor
enum WidgetSnapshotWriter {
    static func write(store: LibraryStore) {
        guard let games = try? store.games(), let plans = try? store.plans() else { return }
        let chasing = games
            .filter { plans[$0.id] == .chasing && !$0.isCompleted }
            .sorted { $0.progress > $1.progress }
        let close = games
            .filter { plans[$0.id]?.isShelved != true && plans[$0.id] != .chasing }
            .filter { $0.definedPlatinum > 0 && !$0.isPlatinumEarned && $0.progress >= 40 }
            .sorted { $0.progress > $1.progress }
        let shown = Array((chasing + close).prefix(3)).map { game in
            WidgetSnapshot.Game(
                id: game.id,
                name: game.name,
                progress: game.progress,
                hasPlatinum: game.definedPlatinum > 0,
                detail: String(localized: "path.left \(game.defined.total - game.earned.total)")
            )
        }
        let latest = (try? store.earnedTrophies())?.max { $0.earnedAt < $1.earnedAt }
        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            games: shown,
            latestTrophy: latest.map {
                WidgetSnapshot.Trophy(name: $0.name, gameName: $0.gameName, type: $0.type.rawValue, earnedAt: $0.earnedAt)
            },
            level: (try? store.profile())?.level,
            platinums: games.filter(\.isPlatinumEarned).count,
            titles: [
                "chase": String(localized: "widget.chase.title"),
                "latest": String(localized: "widget.latest.title"),
                "empty": String(localized: "widget.empty"),
                "level": String(localized: "library.stat.level.short"),
                "platinums": String(localized: "profile.stat.platinums"),
            ]
        )
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
