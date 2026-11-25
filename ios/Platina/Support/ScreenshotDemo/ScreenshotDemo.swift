import UIKit
import DesignSupport
import PSNKit
import PlatinaCore
import PlatinaStore
import PlatinaAssistant

/// The App Store's screenshots (`-ScreenshotDemo`, scripts/capture_screenshots.sh): the app signed
/// in to a made-up library (`PSNDemo`) with a store in memory, its art drawn on the device
/// (`DemoArt`), Plati answering from a script (`AssistantDemoTransport`), and the person's own side
/// seeded after the first sync: the games they chase, past sessions with a journal, a session
/// running, ticks in the walkthrough, a question to Plati. Nothing reaches PSN, Plati's server or
/// iCloud, and the real store is not touched.
enum ScreenshotDemo {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-ScreenshotDemo")

    /// The game of the screenshots: Emberfall, and the chapter the player is in.
    static let gameId = AssistantDemoTransport.gameId
    static let chapterId = AssistantDemoTransport.currentChapterId

    /// The screen a screenshot opens on (`-ScreenshotScreen game`): the app goes there itself,
    /// the same on a phone and an iPad, so the UI test only waits and takes the picture.
    enum Screen: String {
        case path, library, game, guide, walkthrough, chapter, plati, session, profile

        var tab: AppTab {
            switch self {
            case .path, .session: .path
            case .library, .game, .guide, .walkthrough, .chapter: .games
            case .plati: .plati
            case .profile: .profile
            }
        }

        /// The library opens Emberfall: on a phone over the list, on an iPad beside it.
        var opensGame: Bool { [.library, .game, .guide, .walkthrough, .chapter].contains(self) }

        /// A phone shows the open game, not the list.
        var showsGameOnPhone: Bool { self != .library }

        var section: GameSection {
            switch self {
            case .guide: .guide
            case .walkthrough: .walkthrough
            default: .trophies
            }
        }
    }

    static let screen: Screen? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard isOn, let index = arguments.firstIndex(of: "-ScreenshotScreen"), index + 1 < arguments.count else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()

    /// A client signed in to the demo library, in the app's language.
    static func client() -> PSNClient {
        PSNDemo.client(language: AppLanguage.psnLanguage)
    }

    /// `RemotePhoto` draws the demo's `demo://` pictures.
    @MainActor
    static func installArt() {
        DesignKitPhotoLoader.loader = { key, url in
            let image = DemoArt.image(for: url)
            if let image { images[key] = image }
            return image
        }
        DesignKitPhotoLoader.cached = { key in images[key] }
    }

    @MainActor private static var images: [String: UIImage] = [:]

    // MARK: The person's side

    /// After the first sync: plans, sessions, the walkthrough's ticks, then the question to Plati.
    @MainActor
    static func prepare(_ app: AppModel) async {
        let store = app.store
        let now = Date()
        for (id, status) in plans {
            try? store.setPlan(status, for: id, at: now)
        }

        // Past sessions, oldest first, each around the trophy it earned.
        let english = AppLanguage.code == "en"
        for past in pastSessions {
            let start = now.addingTimeInterval(-past.daysAgo * 86_400 - past.hours * 1_800)
            guard let session = try? store.startSession(gameId: past.gameId, at: start) else { continue }
            try? store.recordEarned(past.earned, in: session)
            try? store.endSession(session, at: start.addingTimeInterval(past.hours * 3_600))
            if let summary = past.summary {
                try? store.setSummary(english ? summary.en : summary.ru, nextSteps: english ? summary.nextEn : summary.nextRu, for: session)
            }
        }
        // The session now: an hour and a half in, a trophy earned, two goals.
        if let running = try? store.startSession(gameId: gameId, at: now.addingTimeInterval(-84 * 60)) {
            try? store.setGoals([8, 7], for: running)
            try? store.recordEarned([19], in: running)
        }
        app.sessions.adoptRunningSession()

        // The walkthrough: the plan, the current chapter, two steps ticked.
        let walkthroughs = app.assistant.walkthroughs
        await walkthroughs.fetchCached(gameId: gameId)
        await walkthroughs.fetchCachedChapter(gameId: gameId, chapterId: AssistantDemoTransport.currentChapterId)
        for step in AssistantDemoTransport.checkedStepIds {
            walkthroughs.setStep(step, done: true, gameId: gameId, chapterId: AssistantDemoTransport.currentChapterId)
        }
        await app.assistant.guides.fetchCached(gameId: gameId)

        // Plati's answer, with its cards, in the Plati tab.
        await app.assistant.thread(gameId: nil).send(AssistantDemoTransport.question(language: AppLanguage.code))
    }

    private static let plans: [(String, GamePlanStatus)] = [
        (gameId, .chasing),
        ("NPWR90003_00", .chasing), // Neon Rally Zero
        ("NPWR90005_00", .chasing), // Hollowmere
        ("NPWR90007_00", .later), // Ironclad Vanguard
    ]

    private struct PastSession {
        let gameId: String
        let daysAgo: Double
        let hours: Double
        let earned: [Int]
        var summary: (en: String, ru: String, nextEn: String, nextRu: String)?
    }

    private static let pastSessions: [PastSession] = [
        PastSession(gameId: gameId, daysAgo: 11, hours: 2.2, earned: [13]),
        PastSession(gameId: "NPWR90005_00", daysAgo: 9.4, hours: 1.4, earned: []),
        PastSession(gameId: gameId, daysAgo: 9, hours: 1.8, earned: [12]),
        PastSession(gameId: gameId, daysAgo: 7, hours: 2.5, earned: [16]),
        PastSession(gameId: gameId, daysAgo: 5, hours: 1.6, earned: [17]),
        PastSession(gameId: gameId, daysAgo: 4, hours: 2.0, earned: [20]),
        PastSession(gameId: gameId, daysAgo: 3, hours: 1.7, earned: [21]),
        PastSession(gameId: "NPWR90003_00", daysAgo: 2.6, hours: 1.2, earned: []),
        PastSession(
            gameId: gameId, daysAgo: 2, hours: 2.3, earned: [18],
            summary: (
                "Crossed the Blackwood at night and earned Night Rider. Mira's quest and the golden carp are done: nothing missable is left behind.",
                "Пересекли Чёрный лес ночью и получили «Ночного всадника». Задание Миры и золотой карп готовы: ничего пропускаемого позади не осталось.",
                "Chapter 6: the Citadel Gate. Save before the oath.",
                "Глава 6: врата Цитадели. Сохранитесь перед клятвой."
            )
        ),
    ]
}
