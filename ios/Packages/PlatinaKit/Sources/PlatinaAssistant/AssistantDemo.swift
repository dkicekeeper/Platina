import Foundation

/// Plati's side of the screenshots' made-up library (`PSNDemo` in PSNKit, `-ScreenshotDemo` in
/// the app): a guide, a walkthrough plan and the current chapter's steps for the invented
/// "Emberfall: The Last Crown", and a scripted answer to the question the demo asks, with its
/// cards. It answers like the server does, so the app's own conversation loop, tools and screens
/// show it; nothing leaves the device.
public struct AssistantDemoTransport: AssistantTransport, WalkthroughTransport {
    /// Emberfall's trophy list (`PSNDemo`).
    public static let gameId = "NPWR90001_00"
    /// The chapter the player is in: before the choice at the Citadel's gate.
    public static let currentChapterId = "c6"
    /// Steps the player has ticked in it.
    public static let checkedStepIds = ["s1", "s2"]

    /// What the demo asks Plati.
    public static func question(language: String) -> String {
        text(language, "What's next in this chapter?", "Что дальше в этой главе?")
    }

    public init() {}

    static func text(_ language: String, _ en: String, _ ru: String) -> String {
        language == "en" ? en : ru
    }

    static let generatedAt = "2026-11-20T10:00:00Z"
    static func sources(_ language: String) -> [Guide.Source] {
        [Guide.Source(id: "s1", title: text(language, "Emberfall community wiki", "Вики сообщества Emberfall"), url: "https://example.com/emberfall")]
    }

    // MARK: AssistantTransport

    /// The question → the cards (a warning, the chapter's next steps, quick replies) → the text.
    public func turn(_ request: AssistantTurnRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let language = request.language
        let answeredTools = request.messages.last?.content.contains { $0["type"]?.stringValue == "tool_result" } == true
        let events: [AssistantStreamEvent]
        if answeredTools {
            let reply = Self.text(
                language,
                "You're in chapter 6, The Citadel Gate, two steps done. Ahead: the Gate Sentinel and two more Ember Shards, which make 33 of 40. Mira's quest and the golden carp are already yours, so the point of no return is safe to pass.",
                "Вы в главе 6 «Врата Цитадели», два шага позади. Впереди Страж врат и ещё два осколка углей — будет 33 из 40. Задание Миры и золотой карп у вас уже есть, так что точку невозврата можно проходить спокойно."
            )
            events = [.text(reply), .done(AssistantTurnDone(content: [["type": "text", "text": .string(reply)]], stopReason: "end_turn"))]
        } else {
            let warning: JSONValue = [
                "kind": "choice",
                "title": .string(Self.text(language, "A choice at the gate", "Выбор у ворот")),
                "text": .string(Self.text(
                    language,
                    "Before the Citadel there is a choice tied to a hidden trophy. Step 6 says which, on a tap.",
                    "Перед Цитаделью будет выбор, связанный со скрытым трофеем. Какой — в шаге 6, по нажатию."
                )),
            ]
            let checklist: JSONValue = [
                "game_id": .string(Self.gameId), "chapter_id": .string(Self.currentChapterId),
                "step_ids": ["s3", "s4", "s5", "s6", "s7"],
            ]
            let replies: JSONValue = ["replies": [
                .string(Self.text(language, "Done", "Готово")),
                .string(Self.text(language, "How to beat the Sentinel?", "Как победить Стража?")),
                .string(Self.text(language, "Where am I?", "Где я?")),
            ]]
            events = [
                .tool(name: "get_walkthrough"),
                .done(AssistantTurnDone(content: [
                    ["type": "tool_use", "id": "demo-1", "name": "show_warning", "input": warning],
                    ["type": "tool_use", "id": "demo-2", "name": "show_checklist", "input": checklist],
                    ["type": "tool_use", "id": "demo-3", "name": "suggest_replies", "input": replies],
                ], stopReason: "tool_use")),
            ]
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    public func guide(_ request: GuideRequest) -> AsyncThrowingStream<GuideStreamEvent, Error> {
        let guide = Self.guide(gameId: request.game.npCommunicationId, language: request.language)
        return AsyncThrowingStream { continuation in
            if let guide { continuation.yield(.guide(guide)) } else { continuation.yield(.error(code: "unavailable", retryable: false)) }
            continuation.finish()
        }
    }

    public func cachedGuide(gameId: String, language: String) async throws -> Guide? {
        Self.guide(gameId: gameId, language: language)
    }

    // MARK: WalkthroughTransport

    public func walkthrough(_ request: GuideRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error> {
        let plan = Self.walkthrough(gameId: request.game.npCommunicationId, language: request.language)
        return AsyncThrowingStream { continuation in
            if let plan { continuation.yield(.walkthrough(plan)) } else { continuation.yield(.error(code: "unavailable", retryable: false)) }
            continuation.finish()
        }
    }

    public func chapter(_ request: ChapterRequest) -> AsyncThrowingStream<WalkthroughStreamEvent, Error> {
        let steps = Self.chapter(gameId: request.game.npCommunicationId, language: request.language, chapterId: request.chapterId)
        return AsyncThrowingStream { continuation in
            if let steps { continuation.yield(.chapter(steps)) } else { continuation.yield(.error(code: "unavailable", retryable: false)) }
            continuation.finish()
        }
    }

    public func cachedWalkthrough(gameId: String, language: String) async throws -> Walkthrough? {
        Self.walkthrough(gameId: gameId, language: language)
    }

    public func cachedChapter(gameId: String, language: String, chapterId: String) async throws -> ChapterSteps? {
        Self.chapter(gameId: gameId, language: language, chapterId: chapterId)
    }

    // MARK: Content

    public static func guide(gameId: String, language: String) -> Guide? {
        guard gameId == Self.gameId else { return nil }
        let t = { (en: String, ru: String) in text(language, en, ru) }
        return Guide(
            gameId: gameId,
            language: language,
            generatedAt: generatedAt,
            summary: Guide.Summary(
                difficulty: 6, hoursMin: 45, hoursMax: 55, playthroughs: 1, onlineTrophies: 0,
                missableTrophies: 3, glitchedTrophies: 0, difficultyAffects: false,
                overview: t(
                    "One careful playthrough with a save before the Citadel. The bosses ask for patience more than skill; the shards and echoes are the long part.",
                    "Одно внимательное прохождение с сохранением перед Цитаделью. Боссы требуют скорее терпения, чем мастерства; дольше всего — осколки и отзвуки."
                )
            ),
            steps: [
                Guide.Step(
                    title: t("The story, with the missables", "Сюжет и пропускаемое"),
                    text: t("Finish Mira's quest before the Drowned King and catch the golden carp before the Citadel.", "Закончите задание Миры до Утонувшего короля и поймайте золотого карпа до Цитадели."),
                    trophyIds: [9, 14, 6]
                ),
                Guide.Step(
                    title: t("The choice at the gate", "Выбор у ворот"),
                    text: t("Save before the Citadel's gate: one answer there earns a hidden trophy.", "Сохранитесь перед воротами Цитадели: один из ответов там даёт скрытый трофей."),
                    trophyIds: [10]
                ),
                Guide.Step(
                    title: t("Shards and echoes", "Осколки и отзвуки"),
                    text: t("After the ending every region stays open: collect the rest with the map's markers.", "После финала все области открыты: доберите остальное по меткам на карте."),
                    trophyIds: [7, 8, 17]
                ),
                Guide.Step(
                    title: t("Tides of Ash", "Приливы пепла"),
                    text: t("The DLC opens from the Shore of Bones; its sovereign is the hardest fight.", "Дополнение открывается с Берега костей; его владыка — самый трудный бой."),
                    trophyIds: [20, 21, 22]
                ),
            ],
            missable: [
                Guide.Missable(trophyId: 9, note: t("Mira's quest ends when the Drowned King falls.", "Задание Миры пропадает после победы над Утонувшим королём.")),
                Guide.Missable(trophyId: 10, note: t("Decided at the Citadel's gate.", "Решается у ворот Цитадели.")),
                Guide.Missable(trophyId: 14, note: t("The Mere closes once you enter the Citadel.", "Озёрье закрывается после входа в Цитадель.")),
            ],
            tips: [
                Guide.Tip(trophyId: 8, text: t("Shards glow at night: look for them after dark.", "Осколки светятся ночью: ищите их в темноте."), sourceIds: ["s1"]),
                Guide.Tip(trophyId: 12, text: t("The Gate Warden is the easiest boss for it: stay behind his left leg.", "Проще всего на Страже ворот: держитесь у его левой ноги."), sourceIds: ["s1"]),
            ],
            sources: sources(language),
            stratege: nil
        )
    }

    public static func walkthrough(gameId: String, language: String) -> Walkthrough? {
        guard gameId == Self.gameId else { return nil }
        let t = { (en: String, ru: String) in text(language, en, ru) }
        let shards = t("Ember Shards", "Осколки углей")
        return Walkthrough(
            gameId: gameId,
            language: language,
            generatedAt: generatedAt,
            overview: t(
                "Eight chapters and a DLC. Three trophies can be lost: Mira's quest, the golden carp and a choice at the Citadel's gate; everything else waits for the cleanup.",
                "Восемь глав и дополнение. Потерять можно три трофея: задание Миры, золотого карпа и выбор у ворот Цитадели; всё остальное ждёт зачистки."
            ),
            playthroughs: 1,
            chapters: [
                .init(id: "c1", title: t("The Ember Shrine", "Святилище углей"), summary: t("Wake by the shrine and learn to fight.", "Пробуждение у святилища и первые бои."),
                      trophyIds: [1], completionTrophyId: 1, sourceIds: ["s1"]),
                .init(id: "c2", title: t("The Ashen Road", "Пепельный тракт"), summary: t("The road to the gate and its warden.", "Дорога к воротам и их страж."),
                      collectibles: [.init(kind: shards, count: 6)], trophyIds: [2, 3, 4], completionTrophyId: 3, sourceIds: ["s1"]),
                .init(id: "c3", title: t("Varn, City of Bells", "Варн, город колоколов"), summary: t("A city of three bells, and Mira.", "Город трёх колоколов и Мира."),
                      missable: [.init(trophyId: 9, note: t("Mira's quest starts here.", "Здесь начинается задание Миры."))],
                      collectibles: [.init(kind: shards, count: 7)], trophyIds: [9, 11, 5], completionTrophyId: 11, sourceIds: ["s1"]),
                .init(id: "c4", title: t("The Drowned Mere", "Утонувшее Озёрье"), summary: t("Flooded villages and their king.", "Затопленные деревни и их король."),
                      missable: [.init(trophyId: 14, note: t("The golden carp lives here.", "Здесь водится золотой карп."))],
                      collectibles: [.init(kind: shards, count: 6)], trophyIds: [6, 14], completionTrophyId: 6, sourceIds: ["s1"]),
                .init(id: "c5", title: t("Blackwood", "Чёрный лес"), summary: t("A forest best crossed at night.", "Лес, который лучше проходить ночью."),
                      collectibles: [.init(kind: shards, count: 6)], trophyIds: [18, 16], completionTrophyId: 18, sourceIds: ["s1"]),
                .init(id: "c6", title: t("The Citadel Gate", "Врата Цитадели"), summary: t("The last stop before the Citadel.", "Последняя остановка перед Цитаделью."),
                      missable: [.init(trophyId: 10, note: t("Decided at the gate.", "Решается у ворот."))],
                      choices: [t("The oath at the gate", "Клятва у ворот")],
                      collectibles: [.init(kind: shards, count: 2)], trophyIds: [10], sourceIds: ["s1"]),
                .init(id: "c7", title: t("The Crownless Throne", "Трон без короны"), summary: t("The Citadel, up to its throne.", "Цитадель, до самого трона."),
                      collectibles: [.init(kind: shards, count: 5)], trophyIds: [15], completionTrophyId: 15, sourceIds: ["s1"]),
                .init(id: "c8", title: t("Tides of Ash (DLC)", "Приливы пепла (DLC)"), summary: t("The shore beyond the map.", "Берег за краем карты."),
                      collectibles: [.init(kind: shards, count: 8)], trophyIds: [20, 21, 22], completionTrophyId: 22, sourceIds: ["s1"]),
            ],
            cleanup: t(
                "- Ember Shards: the map marks the regions where some are left.\n- The 12 Echoes: listen at shrines at night.\n- Cartographer: the last fog is in the Blackwood's north.",
                "- Осколки углей: карта отмечает области, где они ещё остались.\n- 12 отзвуков: слушайте у святилищ ночью.\n- «Картограф»: последний туман — на севере Чёрного леса."
            ),
            sources: sources(language)
        )
    }

    public static func chapter(gameId: String, language: String, chapterId: String) -> ChapterSteps? {
        guard gameId == Self.gameId, chapterId == currentChapterId else { return nil }
        let t = { (en: String, ru: String) in text(language, en, ru) }
        let shard = t("Ember Shard", "Осколок углей")
        return ChapterSteps(
            gameId: gameId,
            language: language,
            chapterId: chapterId,
            walkthroughGeneratedAt: generatedAt,
            generatedAt: generatedAt,
            steps: [
                .init(id: "s1", kind: .path, text: t(
                    "From the camp in **Blackwood**, follow the river north to the Citadel's outer wall.",
                    "Из лагеря в **Чёрном лесу** идите вдоль реки на север, к внешней стене Цитадели."
                ), sourceId: "s1"),
                .init(id: "s2", kind: .path, text: t(
                    "Climb the watchtower by the wall and kick down the ladder: a shortcut back to the camp.",
                    "Поднимитесь на сторожевую башню у стены и сбросьте лестницу — короткий путь к лагерю."
                ), sourceId: "s1"),
                .init(id: "s3", kind: .boss, text: t(
                    "**The Gate Sentinel.** Stay close and parry his second swing; at half health he calls hounds, kill them first.",
                    "**Страж врат.** Держитесь вплотную и парируйте второй удар; на половине здоровья он зовёт гончих — сначала их."
                ), sourceId: "s1"),
                .init(id: "s4", kind: .collectible, text: t(
                    "In the guardhouse after the fight, on the top shelf behind the barrels.",
                    "В караульной после боя, на верхней полке за бочками."
                ), trophyIds: [8], collectible: .init(kind: shard, number: 32), sourceId: "s1"),
                .init(id: "s5", kind: .tip, text: t(
                    "Rest at the gate's shrine and spend your embers: the Citadel is much harder.",
                    "Отдохните у святилища у ворот и потратьте угли: в Цитадели заметно сложнее."
                ), sourceId: "s1"),
                .init(id: "s6", kind: .choice, text: t(
                    "Captain Oren asks you to swear the oath. **Refuse** it for *Oathbreaker*; save first to see the other answer.",
                    "Капитан Орен просит принести клятву. **Откажитесь** — это «Клятвопреступник»; сохранитесь, чтобы увидеть другой ответ."
                ), trophyIds: [10], spoiler: true, sourceId: "s1"),
                .init(id: "s7", kind: .pointOfNoReturn, text: t(
                    "Once you enter the Citadel, Varn and the Mere close until the ending.",
                    "После входа в Цитадель Варн и Озёрье закрыты до финала."
                ), sourceId: "s1"),
                .init(id: "s8", kind: .collectible, text: t(
                    "In the Citadel's first hall, under the left staircase.",
                    "В первом зале Цитадели, под левой лестницей."
                ), trophyIds: [8], collectible: .init(kind: shard, number: 33), sourceId: "s1"),
            ],
            sources: sources(language)
        )
    }
}
