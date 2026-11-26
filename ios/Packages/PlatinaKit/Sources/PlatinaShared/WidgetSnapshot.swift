import Foundation

/// What the home screen widgets show (docs/archive/plans/2026-11-20-stages.md, stage 4): the app writes it after every
/// sync into the App Group's container; the widget extension reads it. Texts are prepared by the
/// app in its language, so the extension needs no strings of its own.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Game: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        /// 0–100.
        public let progress: Int
        public let hasPlatinum: Bool
        /// "12 trophies left".
        public let detail: String

        public init(id: String, name: String, progress: Int, hasPlatinum: Bool, detail: String) {
            self.id = id
            self.name = name
            self.progress = progress
            self.hasPlatinum = hasPlatinum
            self.detail = detail
        }
    }

    public struct Trophy: Codable, Sendable, Equatable {
        public let name: String
        public let gameName: String
        /// `platinum`, `gold`, `silver`, `bronze`.
        public let type: String
        public let earnedAt: Date

        public init(name: String, gameName: String, type: String, earnedAt: Date) {
            self.name = name
            self.gameName = gameName
            self.type = type
            self.earnedAt = earnedAt
        }
    }

    public let updatedAt: Date
    /// "Going for platinum" first, then the closest to it.
    public let games: [Game]
    public let latestTrophy: Trophy?
    public let level: Int?
    public let platinums: Int
    /// The widgets' captions in the app's language.
    public let titles: [String: String]

    public init(updatedAt: Date, games: [Game], latestTrophy: Trophy?, level: Int?, platinums: Int, titles: [String: String]) {
        self.updatedAt = updatedAt
        self.games = games
        self.latestTrophy = latestTrophy
        self.level = level
        self.platinums = platinums
        self.titles = titles
    }

    public func title(_ key: String) -> String { titles[key] ?? key }

    public static let placeholder = WidgetSnapshot(
        updatedAt: Date(timeIntervalSince1970: 0),
        games: [Game(id: "preview", name: "Astro Bot", progress: 72, hasPlatinum: true, detail: "9")],
        latestTrophy: Trophy(name: "Platinum", gameName: "Astro Bot", type: "platinum", earnedAt: Date(timeIntervalSince1970: 0)),
        level: 412,
        platinums: 41,
        titles: [:]
    )
}

/// The snapshot's file in the App Group container shared by the app and its widgets.
public enum WidgetSnapshotStore {
    public static let appGroup = "group.dakacom.Platina"
    static let fileName = "widget-snapshot.json"

    /// nil when the App Group is not available (an unsigned build): the widgets show their
    /// placeholder then.
    public static func url(fileManager: FileManager = .default) -> URL? {
        #if canImport(Darwin)
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
        #else
        nil
        #endif
    }

    public static func write(_ snapshot: WidgetSnapshot, to url: URL? = url()) {
        guard let url, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL? = url()) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
