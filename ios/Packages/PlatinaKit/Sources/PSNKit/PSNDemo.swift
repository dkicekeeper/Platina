import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A made-up PlayStation library for the App Store's screenshots (`-ScreenshotDemo`): eight
/// invented PS5 games with their trophies, DLC, play time and art, answered by
/// `PSNDemoTransport` the way PSN answers for a real account, so the app's own sync reads them.
/// No real game, picture or name: the art is drawn by the app (`demo://` addresses), and nothing
/// leaves the device.
public enum PSNDemo {
    /// The account the demo is signed in to.
    public static let accountId = "7700000000000000001"
    public static let onlineId = "platina_hunter"

    /// Tokens valid for years: the client thinks it is signed in and never refreshes them.
    public static func tokens(now: Date = Date()) -> PSNTokens {
        let far = now.addingTimeInterval(10 * 365 * 24 * 3600)
        return PSNTokens(accessToken: "demo", accessTokenExpiresAt: far, refreshToken: "demo", refreshTokenExpiresAt: far)
    }

    /// A client signed in to the demo account, answered by `PSNDemoTransport`.
    public static func client(language: String, now: Date = Date()) -> PSNClient {
        PSNClient(
            store: InMemoryTokenStore(tokens(now: now)),
            transport: PSNDemoTransport(library: Library(now: now)),
            language: language
        )
    }

    // MARK: The library

    /// One invented game.
    public struct Game: Sendable {
        /// Names the art the app draws for it (`demo://art/<slug>/…`).
        public let slug: String
        public let npCommunicationId: String
        public let titleId: String
        public let name: String
        public let trophies: [Trophy]
        /// The DLC's group, if it has one: `001`.
        public let dlc: (en: String, ru: String)?
        public let hours: Double
        public let playCount: Int
        /// Days ago it was first and last played.
        public let firstPlayedDaysAgo: Double
        public let lastPlayedDaysAgo: Double

        public var isPlatinumEarned: Bool { trophies.contains { $0.type == "platinum" && $0.earnedDaysAgo != nil } }
    }

    public struct Trophy: Sendable {
        public let id: Int
        /// `bronze`, `silver`, `gold`, `platinum`.
        public let type: String
        public let en: (name: String, detail: String)
        public let ru: (name: String, detail: String)
        public let hidden: Bool
        /// `default` or `001`.
        public let group: String
        /// nil: not earned.
        public let earnedDaysAgo: Double?
        /// A progress trophy: how far along of how many.
        public let progress: (value: Int, target: Int)?
        /// 0 ultra rare … 3 common, and the share of players who have it.
        public let rarity: (rare: Int, rate: String)
    }

    /// The games, the newest played first, with every date counted back from `now`.
    public struct Library: Sendable {
        public let now: Date
        public let games: [Game]

        public init(now: Date = Date()) {
            self.now = now
            games = PSNDemo.games
        }

        func date(daysAgo: Double) -> Date {
            now.addingTimeInterval(-daysAgo * 24 * 3600)
        }
    }

    // MARK: The games

    static let games: [Game] = [
        emberfall,
        made(slug: "starwake", number: 2, name: "Starwake", earnedShare: 1, counts: (7, 3, 1), hours: 41.5, playCount: 63, first: 96, last: 22,
             platinum: ("Wake of Stars", "След звёзд")),
        made(slug: "neonrally", number: 3, name: "Neon Rally Zero", earnedShare: 0.64, counts: (24, 9, 3), hours: 27.2, playCount: 48, first: 70, last: 3,
             platinum: ("Zero to Legend", "От нуля до легенды")),
        made(slug: "mosswick", number: 4, name: "Mosswick", earnedShare: 1, counts: (18, 6, 2), hours: 19.8, playCount: 31, first: 140, last: 101,
             platinum: ("Heart of the Grove", "Сердце рощи")),
        made(slug: "hollowmere", number: 5, name: "Hollowmere", earnedShare: 0.41, counts: (20, 8, 3), hours: 12.4, playCount: 17, first: 35, last: 9,
             platinum: ("Through the Fog", "Сквозь туман")),
        made(slug: "lumentide", number: 6, name: "Lumen Tide", earnedShare: 1, counts: (12, 5, 2), hours: 14.1, playCount: 26, first: 210, last: 182,
             platinum: ("All Lights Lit", "Все огни горят")),
        made(slug: "ironclad", number: 7, name: "Ironclad Vanguard", earnedShare: 0.23, counts: (30, 10, 4), hours: 9.6, playCount: 14, first: 18, last: 6,
             platinum: ("Last Line", "Последний рубеж")),
        made(slug: "skyforge", number: 8, name: "Skyforge Tactics", earnedShare: 0.57, counts: (22, 8, 3), hours: 33.7, playCount: 40, first: 120, last: 45,
             platinum: ("Grand Strategist", "Великий стратег")),
    ]

    /// The game of the screenshots: in progress, with DLC, a progress trophy, a hidden one and a
    /// missable one.
    static let emberfall: Game = {
        // type, English name and detail, Russian name and detail, days ago earned (nil: not yet)
        let base: [(String, String, String, String, String, Double?)] = [
            ("platinum", "The Last Crown", "Earn every other trophy.", "Последняя корона", "Получите все остальные трофеи.", nil),
            ("bronze", "First Spark", "Light the first Ember Shrine.", "Первая искра", "Зажгите первое святилище углей.", 38),
            ("bronze", "Ashen Road", "Reach the Ashen Road.", "Пепельный тракт", "Доберитесь до Пепельного тракта.", 37),
            ("silver", "Warden of the Gate", "Defeat the Gate Warden.", "Страж ворот", "Победите Стража ворот.", 35),
            ("bronze", "Smith's Apprentice", "Upgrade a weapon to +5.", "Ученик кузнеца", "Улучшите оружие до +5.", 33),
            ("bronze", "Lantern Bearer", "Find the Lantern of Embers.", "Фонарщик", "Найдите Фонарь углей.", 30),
            ("gold", "Drowned King", "Defeat the Drowned King.", "Утонувший король", "Победите Утонувшего короля.", 21),
            ("bronze", "Cartographer", "Uncover every region of the map.", "Картограф", "Откройте все области карты.", nil),
            ("silver", "Ember Collector", "Collect 40 Ember Shards.", "Собиратель углей", "Соберите 40 осколков углей.", nil),
            ("bronze", "Friend of the Hollow", "Complete Mira's quest.", "Друг Пустоши", "Выполните задание Миры.", 18),
            ("gold", "Oathbreaker", "Break the oath at the Citadel's gate.", "Клятвопреступник", "Нарушьте клятву у ворот Цитадели.", nil),
            ("bronze", "Bell Ringer", "Ring all three bells of Varn.", "Звонарь", "Ударьте во все три колокола Варна.", 14),
            ("silver", "Unbroken", "Defeat a boss without taking damage.", "Невредимый", "Победите босса, не получив урона.", 9),
            ("bronze", "Hoarder", "Hold 50,000 embers at once.", "Скопидом", "Держите 50 000 углей одновременно.", 11),
            ("bronze", "Fisher of the Mere", "Catch the golden carp.", "Рыбак Озёрья", "Поймайте золотого карпа.", 16),
            ("gold", "Crownless", "Reach the throne of the Citadel.", "Без короны", "Доберитесь до трона Цитадели.", nil),
            ("bronze", "Alchemist", "Brew every potion.", "Алхимик", "Сварите все зелья.", 7),
            ("silver", "Seeker of Echoes", "Hear all 12 Echoes.", "Искатель отзвуков", "Услышьте все 12 отзвуков.", 5),
            ("bronze", "Night Rider", "Cross the Blackwood at night.", "Ночной всадник", "Пересеките Чёрный лес ночью.", 2),
            ("bronze", "Shieldwall", "Parry 100 attacks.", "Стена щитов", "Отразите 100 атак.", 0.03),
        ]
        let dlc: [(String, String, String, String, String, Double?)] = [
            ("bronze", "Shore of Bones", "Reach the Shore of Bones.", "Берег костей", "Доберитесь до Берега костей.", 4),
            ("silver", "Tide Caller", "Defeat the Tide Caller.", "Зовущий прилив", "Победите Зовущего прилив.", 3),
            ("gold", "Ash Sovereign", "Defeat the Ash Sovereign.", "Пепельный владыка", "Победите Пепельного владыку.", nil),
        ]
        let rows = base.map { ($0, "default") } + dlc.map { ($0, "001") }
        let trophies = rows.enumerated().map { index, row in
            let ((type, enName, enDetail, ruName, ruDetail, earned), group) = row
            return Trophy(
                id: index,
                type: type,
                en: (enName, enDetail),
                ru: (ruName, ruDetail),
                hidden: index == 10,
                group: group,
                earnedDaysAgo: earned,
                progress: index == 8 ? (31, 40) : nil,
                rarity: rarity(type: type, index: index)
            )
        }
        return Game(
            slug: "emberfall", npCommunicationId: "NPWR90001_00", titleId: "PPSA90001_00",
            name: "Emberfall: The Last Crown", trophies: trophies, dlc: ("Tides of Ash", "Приливы пепла"),
            hours: 46.3, playCount: 58, firstPlayedDaysAgo: 39, lastPlayedDaysAgo: 0.01
        )
    }()

    /// Trophy names for the other games, English and Russian.
    static let pool: [(en: String, ru: String)] = [
        ("First Steps", "Первые шаги"), ("Explorer", "Исследователь"), ("Collector", "Коллекционер"),
        ("Champion", "Чемпион"), ("Perfectionist", "Перфекционист"), ("Night Owl", "Полуночник"),
        ("Sharpshooter", "Снайпер"), ("Faster than Wind", "Быстрее ветра"), ("Treasure Hunter", "Охотник за сокровищами"),
        ("Survivor", "Выживший"), ("Strategist", "Стратег"), ("Master", "Мастер"),
        ("Pathfinder", "Следопыт"), ("Unstoppable", "Неудержимый"), ("Craftsman", "Мастеровой"),
        ("Lucky Streak", "Полоса удачи"), ("No Way Back", "Пути назад нет"), ("Old Friend", "Старый друг"),
        ("High Score", "Рекорд"), ("Clean Sweep", "Чистая победа"), ("Long Haul", "Долгий путь"),
        ("Keen Eye", "Зоркий глаз"), ("Steady Hand", "Твёрдая рука"), ("Daredevil", "Сорвиголова"),
        ("Archivist", "Архивариус"), ("Free Spirit", "Вольная душа"), ("Iron Will", "Железная воля"),
        ("Wanderer", "Странник"), ("Quick Learner", "Схватывает на лету"), ("Big Spender", "Транжира"),
        ("Hidden Path", "Тайная тропа"), ("Ace", "Ас"), ("Guardian", "Хранитель"),
        ("Patient One", "Терпеливый"), ("Full House", "Полный дом"), ("Shadow", "Тень"),
        ("Bright Idea", "Светлая мысль"), ("Gatekeeper", "Привратник"), ("Last Stand", "Последний бой"),
        ("Homecoming", "Возвращение"), ("Untouchable", "Неуязвимый"), ("Fortune", "Удача"),
        ("Echo", "Эхо"), ("Rising Star", "Восходящая звезда"),
    ]

    /// A game whose trophies come from the pool: the first `earnedShare` of them earned, evenly
    /// between the days it was played.
    static func made(
        slug: String,
        number: Int,
        name: String,
        earnedShare: Double,
        counts: (bronze: Int, silver: Int, gold: Int),
        hours: Double,
        playCount: Int,
        first: Double,
        last: Double,
        platinum: (en: String, ru: String)
    ) -> Game {
        let types = Array(repeating: "bronze", count: counts.bronze) + Array(repeating: "silver", count: counts.silver)
            + Array(repeating: "gold", count: counts.gold)
        // Golds and silvers among the bronzes, as games have them, the same on every run.
        let shuffled = types.enumerated()
            .sorted { order($0.element, index: $0.offset, seed: number) < order($1.element, index: $1.offset, seed: number) }
            .map(\.element)
        let earnedCount = Int((Double(types.count) * earnedShare).rounded())
        var trophies: [Trophy] = []
        let complete = earnedShare >= 1
        trophies.append(Trophy(
            id: 0, type: "platinum",
            en: (platinum.en, "Earn every other trophy."), ru: (platinum.ru, "Получите все остальные трофеи."),
            hidden: false, group: "default",
            earnedDaysAgo: complete ? last : nil, progress: nil, rarity: rarity(type: "platinum", index: number)
        ))
        for (offset, type) in shuffled.enumerated() {
            let names = pool[(offset * 7 + number * 5) % pool.count]
            let earned: Double? = offset < earnedCount
                ? first - (first - last) * Double(offset + 1) / Double(max(earnedCount, 1))
                : nil
            trophies.append(Trophy(
                id: offset + 1, type: type,
                en: (names.en, "A trophy of \(name)."), ru: (names.ru, "Трофей игры \(name)."),
                hidden: false, group: "default",
                earnedDaysAgo: earned, progress: nil, rarity: rarity(type: type, index: offset + number)
            ))
        }
        return Game(
            slug: slug,
            npCommunicationId: String(format: "NPWR9%04d_00", number),
            titleId: String(format: "PPSA9%04d_00", number),
            name: name, trophies: trophies, dlc: nil,
            hours: hours, playCount: playCount, firstPlayedDaysAgo: first, lastPlayedDaysAgo: last
        )
    }

    /// A stable shuffle key, so a game's golds land in the same places on every run.
    private static func order(_ type: String, index: Int, seed: Int) -> Int {
        var hash = seed &* 31 &+ index &* 7_919
        for scalar in type.unicodeScalars { hash = hash &* 33 &+ Int(scalar.value) }
        return (hash & 0x7FFF_FFFF) % 9_973
    }

    static func rarity(type: String, index: Int) -> (rare: Int, rate: String) {
        switch type {
        case "platinum": return (0, String(format: "%.1f", 2.1 + Double(index % 5) * 1.3))
        case "gold": return (1, String(format: "%.1f", 6.4 + Double(index % 7) * 1.7))
        case "silver": return (2, String(format: "%.1f", 17.0 + Double(index % 9) * 2.2))
        default: return (3, String(format: "%.1f", 38.0 + Double(index % 11) * 4.1))
        }
    }
}

// MARK: - The transport

/// Answers the PSN requests the app makes with the demo library (`PSNDemo`): the trophy lists,
/// a game's groups, trophies and the person's side of them, the played games with their art,
/// the profile and the trophy summary. Anything else (Game Help, sign-in) is 404.
public struct PSNDemoTransport: HTTPTransport {
    let library: PSNDemo.Library

    public init(library: PSNDemo.Library = PSNDemo.Library()) {
        self.library = library
    }

    public func send(_ request: URLRequest, followRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let english = (request.value(forHTTPHeaderField: "Accept-Language") ?? "").hasPrefix("en")
        let path = url.path.replacingOccurrences(of: "/api/", with: "")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let body = answer(path: path, query: query, english: english),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return (Data(#"{"error":{"code":404,"message":"Not found"}}"#.utf8), Self.response(url, status: 404))
        }
        return (data, Self.response(url, status: 200))
    }

    private static func response(_ url: URL, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }

    // MARK: Routes

    func answer(path: String, query: [URLQueryItem], english: Bool) -> Any? {
        let parts = path.split(separator: "/").map(String.init)
        switch parts {
        case ["trophy", "v1", "users", "me", "trophyTitles"]:
            let titles = library.games.map { title($0) }
            return ["trophyTitles": titles, "totalItemCount": titles.count]
        case ["trophy", "v1", "users", "me", "trophySummary"]:
            return summary()
        case let p where p.count == 6 && p[0] == "userProfile" && p[5] == "profiles":
            return profile()
        case let p where p.count == 6 && p[0] == "userProfile" && p[5] == "basicPresences":
            return ["basicPresence": ["availability": "unavailable", "primaryPlatformInfo": ["onlineStatus": "offline", "platform": "PS5"]]]
        case let p where p.count == 5 && p[2] == "npCommunicationIds" && p[4] == "trophyGroups":
            return game(p[3]).map { groups($0, english: english) }
        case let p where p.count == 7 && p[2] == "npCommunicationIds" && p[6] == "trophies":
            return game(p[3]).map { definitions($0, english: english) }
        case let p where p.count == 9 && p[4] == "npCommunicationIds" && p[8] == "trophies":
            return game(p[5]).map { earnings($0) }
        case let p where p.count == 7 && p[4] == "npCommunicationIds" && p[6] == "trophyGroups":
            return game(p[5]).map { progress($0) }
        case ["gamelist", "v2", "users", "me", "titles"]:
            let titles = library.games.map { played($0) }
            return ["titles": titles, "totalItemCount": titles.count]
        case ["trophy", "v1", "users", "me", "titles", "trophyTitles"]:
            let ids = (query.first { $0.name == "npTitleIds" }?.value ?? "").split(separator: ",").map(String.init)
            let titles = ids.compactMap { id -> [String: Any]? in
                guard let game = library.games.first(where: { $0.titleId == id }) else { return nil }
                return ["npTitleId": id, "trophyTitles": [title(game)]]
            }
            return ["titles": titles]
        default:
            return nil
        }
    }

    private func game(_ id: String) -> PSNDemo.Game? {
        library.games.first { $0.npCommunicationId == id }
    }

    // MARK: Bodies

    private func title(_ game: PSNDemo.Game) -> [String: Any] {
        [
            "npServiceName": "trophy2",
            "npCommunicationId": game.npCommunicationId,
            "trophySetVersion": "01.00",
            "trophyTitleName": game.name,
            "trophyTitleIconUrl": "demo://art/\(game.slug)/icon",
            "trophyTitlePlatform": "PS5",
            "hasTrophyGroups": game.dlc != nil,
            "trophyGroupCount": game.dlc != nil ? 2 : 1,
            "definedTrophies": counts(game.trophies),
            "progress": Self.progress(of: game.trophies),
            "earnedTrophies": counts(game.trophies.filter { $0.earnedDaysAgo != nil }),
            "hiddenFlag": false,
            "lastUpdatedDateTime": Self.text(lastEarned(game) ?? library.date(daysAgo: game.lastPlayedDaysAgo)),
        ]
    }

    private func groups(_ game: PSNDemo.Game, english: Bool) -> [String: Any] {
        var groups: [[String: Any]] = [[
            "trophyGroupId": "default",
            "trophyGroupName": game.name,
            "trophyGroupIconUrl": "demo://art/\(game.slug)/icon",
            "definedTrophies": counts(game.trophies.filter { $0.group == "default" }),
        ]]
        if let dlc = game.dlc {
            groups.append([
                "trophyGroupId": "001",
                "trophyGroupName": english ? dlc.en : dlc.ru,
                "trophyGroupIconUrl": "demo://art/\(game.slug)/dlc",
                "definedTrophies": counts(game.trophies.filter { $0.group == "001" }),
            ])
        }
        return ["trophySetVersion": "01.00", "trophyGroups": groups]
    }

    private func definitions(_ game: PSNDemo.Game, english: Bool) -> [String: Any] {
        let trophies: [[String: Any]] = game.trophies.map { trophy in
            var row: [String: Any] = [
                "trophyId": trophy.id,
                "trophyHidden": trophy.hidden,
                "trophyType": trophy.type,
                "trophyName": english ? trophy.en.name : trophy.ru.name,
                "trophyDetail": english ? trophy.en.detail : trophy.ru.detail,
                "trophyIconUrl": "demo://trophy/\(game.slug)/\(trophy.id)",
                "trophyGroupId": trophy.group,
            ]
            if let progress = trophy.progress {
                row["trophyProgressTargetValue"] = String(progress.target)
            }
            return row
        }
        return ["trophySetVersion": "01.00", "hasTrophyGroups": game.dlc != nil, "trophies": trophies, "totalItemCount": trophies.count]
    }

    private func earnings(_ game: PSNDemo.Game) -> [String: Any] {
        let trophies: [[String: Any]] = game.trophies.map { trophy in
            var row: [String: Any] = [
                "trophyId": trophy.id,
                "trophyHidden": trophy.hidden,
                "earned": trophy.earnedDaysAgo != nil,
                "trophyType": trophy.type,
                "trophyRare": trophy.rarity.rare,
                "trophyEarnedRate": trophy.rarity.rate,
            ]
            if let days = trophy.earnedDaysAgo {
                row["earnedDateTime"] = Self.text(library.date(daysAgo: days))
            }
            if let progress = trophy.progress {
                row["progress"] = String(progress.value)
                row["progressRate"] = progress.value * 100 / progress.target
                row["progressedDateTime"] = Self.text(library.date(daysAgo: 1))
            }
            return row
        }
        return [
            "trophySetVersion": "01.00",
            "hasTrophyGroups": game.dlc != nil,
            "lastUpdatedDateTime": Self.text(lastEarned(game) ?? library.date(daysAgo: game.lastPlayedDaysAgo)),
            "trophies": trophies,
            "totalItemCount": trophies.count,
        ]
    }

    private func progress(_ game: PSNDemo.Game) -> [String: Any] {
        let groupIds = game.dlc != nil ? ["default", "001"] : ["default"]
        let updated = Self.text(lastEarned(game) ?? library.date(daysAgo: game.lastPlayedDaysAgo))
        return [
            "trophySetVersion": "01.00",
            "hiddenFlag": false,
            "progress": Self.progress(of: game.trophies),
            "earnedTrophies": counts(game.trophies.filter { $0.earnedDaysAgo != nil }),
            "trophyGroups": groupIds.map { id in
                let inGroup = game.trophies.filter { $0.group == id }
                return [
                    "trophyGroupId": id,
                    "progress": Self.progress(of: inGroup),
                    "earnedTrophies": counts(inGroup.filter { $0.earnedDaysAgo != nil }),
                    "lastUpdatedDateTime": updated,
                ] as [String: Any]
            },
            "lastUpdatedDateTime": updated,
        ]
    }

    private func played(_ game: PSNDemo.Game) -> [String: Any] {
        let art = "demo://art/\(game.slug)"
        let seconds = Int(game.hours * 3600)
        return [
            "titleId": game.titleId,
            "name": game.name,
            "localizedName": game.name,
            "imageUrl": "\(art)/icon",
            "localizedImageUrl": "\(art)/icon",
            "category": "ps5_native_game",
            "service": "none_purchased",
            "playCount": game.playCount,
            "concept": [
                "id": 90000 + (Int(game.titleId.dropFirst(5).prefix(4)) ?? 0),
                "titleIds": [game.titleId],
                "name": game.name,
                "media": ["audios": [], "videos": [], "images": [
                    ["url": "\(art)/hub", "format": "UNKNOWN", "type": PSNGameArt.gameHubCoverArt],
                    ["url": "\(art)/logo", "format": "UNKNOWN", "type": PSNGameArt.logo],
                ]],
            ] as [String: Any],
            "firstPlayedDateTime": Self.text(library.date(daysAgo: game.firstPlayedDaysAgo)),
            "lastPlayedDateTime": Self.text(library.date(daysAgo: game.lastPlayedDaysAgo)),
            "playDuration": "PT\(seconds / 3600)H\(seconds % 3600 / 60)M\(seconds % 60)S",
        ]
    }

    private func summary() -> [String: Any] {
        let earned = library.games.flatMap(\.trophies).filter { $0.earnedDaysAgo != nil }
        // The demo games, and the years of games before them.
        let all = counts(earned)
        return [
            "accountId": PSNDemo.accountId,
            "trophyLevel": 287,
            "trophyPoint": 98_420,
            "trophyLevelBasePoint": 97_900,
            "trophyLevelNextPoint": 98_800,
            "progress": 58,
            "tier": 3,
            "earnedTrophies": [
                "bronze": (all["bronze"] ?? 0) + 1_420,
                "silver": (all["silver"] ?? 0) + 380,
                "gold": (all["gold"] ?? 0) + 112,
                "platinum": (all["platinum"] ?? 0) + 19,
            ],
        ]
    }

    private func profile() -> [String: Any] {
        [
            "onlineId": PSNDemo.onlineId,
            "aboutMe": "",
            "avatars": [["size": "xl", "url": "demo://art/avatar"]],
            "languages": ["ru-RU"],
            "isPlus": true,
            "isOfficiallyVerified": false,
            "isMe": true,
        ]
    }

    // MARK: Helpers

    private func counts(_ trophies: [PSNDemo.Trophy]) -> [String: Int] {
        var counts = ["bronze": 0, "silver": 0, "gold": 0, "platinum": 0]
        for trophy in trophies { counts[trophy.type, default: 0] += 1 }
        return counts
    }

    private func lastEarned(_ game: PSNDemo.Game) -> Date? {
        game.trophies.compactMap(\.earnedDaysAgo).min().map { library.date(daysAgo: $0) }
    }

    /// PSN's percentage: by points (bronze 15, silver 30, gold 90), the platinum not counted.
    static func progress(of trophies: [PSNDemo.Trophy]) -> Int {
        func points(_ type: String) -> Int {
            switch type {
            case "bronze": 15
            case "silver": 30
            case "gold": 90
            default: 0
            }
        }
        let total = trophies.reduce(0) { $0 + points($1.type) }
        let earned = trophies.filter { $0.earnedDaysAgo != nil }.reduce(0) { $0 + points($1.type) }
        guard total > 0 else { return 0 }
        return earned * 100 / total
    }

    static func text(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
