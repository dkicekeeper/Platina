#if canImport(SwiftData)
import Foundation
import SwiftData
import PSNKit
import PlatinaCore

/// The app's SwiftData container and every write into it. Writes happen on the main context: a
/// sync writes one game at a time (a few dozen trophies), small enough for the main thread,
/// and `@Query` sees each at once.
@MainActor
public final class LibraryStore {
    public static let cacheModels: [any PersistentModel.Type] = [
        GameRecord.self, TrophyRecord.self, TrophyGroupRecord.self, ProfileRecord.self, TitleLinkRecord.self,
    ]
    public static let userModels: [any PersistentModel.Type] = [GamePlanRecord.self, PlaySessionRecord.self, NoteRecord.self]

    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// The container with its two stores. A cache a new version cannot open is started over:
    /// the next sync fills it again. The person's own store is never deleted.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(cacheModels + userModels)
        let cache = ModelConfiguration(
            "cache", schema: Schema(cacheModels), isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        let user = ModelConfiguration(
            "user", schema: Schema(userModels), isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [cache, user])
        } catch where !inMemory {
            let fileManager = FileManager.default
            for suffix in ["", "-shm", "-wal"] {
                try? fileManager.removeItem(at: URL(fileURLWithPath: cache.url.path + suffix))
            }
            return try ModelContainer(for: schema, configurations: [cache, user])
        }
    }

    // MARK: Reading

    public func game(_ id: String) throws -> GameRecord? {
        var descriptor = FetchDescriptor<GameRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func games() throws -> [GameRecord] {
        try context.fetch(FetchDescriptor<GameRecord>())
    }

    public func profile() throws -> ProfileRecord? {
        try context.fetch(FetchDescriptor<ProfileRecord>()).first
    }

    /// What the store remembers about each game's last trophy fetch.
    public func detailStates() throws -> [String: DetailState] {
        var states: [String: DetailState] = [:]
        for game in try games() where game.detailsLastUpdated != nil {
            states[game.id] = DetailState(
                lastUpdated: game.detailsLastUpdated,
                trophySetVersion: game.detailsVersion,
                hasGroups: !game.groups.isEmpty
            )
        }
        return states
    }

    public func knownTitleIds() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<TitleLinkRecord>()).map(\.titleId))
    }

    public func titleLinks() throws -> [String: [String]] {
        Dictionary(
            try context.fetch(FetchDescriptor<TitleLinkRecord>()).map { ($0.titleId, $0.listIds) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func plans() throws -> [String: GamePlanStatus] {
        Dictionary(
            try context.fetch(FetchDescriptor<GamePlanRecord>()).map { ($0.gameId, $0.status) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: Writing what PSN says

    public func save(summary: TrophySummary, profile: PSNProfile?, syncedAt: Date?) throws {
        let record: ProfileRecord
        if let existing = try self.profile() {
            if existing.accountId != summary.accountId {
                // Another account: nothing of the old one stays.
                try eraseCache()
                record = ProfileRecord(summary: summary)
                context.insert(record)
            } else {
                record = existing
            }
        } else {
            record = ProfileRecord(summary: summary)
            context.insert(record)
        }
        record.update(summary: summary, profile: profile)
        if let syncedAt { record.lastSyncedAt = syncedAt }
        try context.save()
    }

    public func markSynced(at date: Date) throws {
        try profile()?.lastSyncedAt = date
        try context.save()
    }

    /// The person's PS5 trophy lists: new ones added, known ones updated, hidden ones removed.
    public func save(titles: [TrophyTitle]) throws {
        let existing = Dictionary(try games().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(titles.map(\.id))
        for title in titles {
            if let game = existing[title.id] {
                game.update(from: title)
            } else {
                context.insert(GameRecord(title: title))
            }
        }
        for (id, game) in existing where !ids.contains(id) {
            // The cascade rule does it too; done by hand so nothing is left over whatever the
            // SwiftData version.
            for trophy in game.trophies { context.delete(trophy) }
            for group in game.groups { context.delete(group) }
            context.delete(game)
        }
        try context.save()
    }

    /// A game's trophies (and its groups, when fetched) as PSN has them now.
    public func save(trophies: [Trophy], groups: [TrophyGroup]?, for title: TrophyTitle) throws {
        let game: GameRecord
        if let existing = try self.game(title.id) {
            game = existing
        } else {
            game = GameRecord(title: title)
            context.insert(game)
        }
        game.update(from: title)

        let stored = Dictionary(game.trophies.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<Int>()
        for trophy in trophies {
            seen.insert(trophy.id)
            if let record = stored[trophy.id] {
                record.update(from: trophy)
            } else {
                let record = TrophyRecord(gameId: game.id, trophy: trophy)
                context.insert(record)
                record.game = game
            }
        }
        for (id, record) in stored where !seen.contains(id) {
            context.delete(record)
        }

        if let groups {
            let storedGroups = Dictionary(game.groups.map { ($0.groupId, $0) }, uniquingKeysWith: { first, _ in first })
            var seenGroups = Set<String>()
            for group in groups {
                seenGroups.insert(group.trophyGroupId)
                if let record = storedGroups[group.trophyGroupId] {
                    record.update(from: group)
                } else {
                    let record = TrophyGroupRecord(gameId: game.id, group: group)
                    context.insert(record)
                    record.game = game
                }
            }
            for (id, record) in storedGroups where !seenGroups.contains(id) {
                context.delete(record)
            }
        }

        game.detailsLastUpdated = title.lastUpdatedDateTime
        game.detailsVersion = title.trophySetVersion
        try context.save()
    }

    /// The trophy lists of the titles just asked about; a title with none is remembered too, so
    /// it is not asked again.
    public func save(links: [TitleTrophyLink], asked: [String], at date: Date) throws {
        let known = try knownTitleIds()
        let answered = Dictionary(links.map { ($0.npTitleId, $0.trophyTitles.map(\.npCommunicationId)) }, uniquingKeysWith: { first, _ in first })
        for titleId in asked where !known.contains(titleId) {
            context.insert(TitleLinkRecord(titleId: titleId, listIds: answered[titleId] ?? [], checkedAt: date))
        }
        try context.save()
    }

    public func save(playTime: [String: PlayTime]) throws {
        for game in try games() {
            guard let time = playTime[game.id] else { continue }
            game.playSeconds = time.seconds
            game.firstPlayed = time.firstPlayed
            game.lastPlayed = time.lastPlayed
            game.playCount = time.playCount
            game.coverURLString = time.imageURL?.absoluteString
        }
        try context.save()
    }

    /// Everything PSN gave: on sign-out, or when another account signs in. The person's own data
    /// stays.
    public func eraseCache() throws {
        // Object by object, not `delete(model:)`: a batch delete goes straight to the store, and
        // the main context kept handing out the objects it already had.
        for trophy in try context.fetch(FetchDescriptor<TrophyRecord>()) { context.delete(trophy) }
        for group in try context.fetch(FetchDescriptor<TrophyGroupRecord>()) { context.delete(group) }
        for game in try games() { context.delete(game) }
        for profile in try context.fetch(FetchDescriptor<ProfileRecord>()) { context.delete(profile) }
        for link in try context.fetch(FetchDescriptor<TitleLinkRecord>()) { context.delete(link) }
        try context.save()
    }

    // MARK: The person's own data

    public func setPlan(_ status: GamePlanStatus, for gameId: String, at date: Date = Date()) throws {
        let descriptor = FetchDescriptor<GamePlanRecord>(predicate: #Predicate { $0.gameId == gameId })
        let existing = try context.fetch(descriptor)
        if let plan = existing.first {
            plan.statusRaw = status.rawValue
            plan.updatedAt = date
            for duplicate in existing.dropFirst() {
                context.delete(duplicate)
            }
        } else {
            context.insert(GamePlanRecord(gameId: gameId, status: status, updatedAt: date))
        }
        try context.save()
    }

    /// A game's progress and the person's side of its trophies, fetched without the trophies'
    /// names: what a session's check brings. Returns the trophies earned since the last look.
    @discardableResult
    public func save(progress: TitleProgress, earnings: [TrophyEarning], for gameId: String) throws -> [TrophyRecord] {
        guard let game = try game(gameId) else { return [] }
        let byId = Dictionary(game.trophies.map { ($0.trophyId, $0) }, uniquingKeysWith: { first, _ in first })
        var newlyEarned: [TrophyRecord] = []
        for earning in earnings {
            guard let record = byId[earning.trophyId] else { continue }
            if earning.earned, !record.isEarned {
                newlyEarned.append(record)
            }
            record.isEarned = earning.earned
            record.earnedAt = earning.earnedDateTime
            record.earnedRate = earning.earnedRate ?? record.earnedRate
            record.rarityRaw = earning.trophyRare?.rawValue ?? record.rarityRaw
            if record.progressTarget != nil {
                record.progressCurrent = earning.progressCurrent ?? record.progressCurrent
                record.progressUpdatedAt = earning.progressedDateTime ?? record.progressUpdatedAt
            }
        }
        game.progress = progress.progress
        game.earnedBronze = progress.earnedTrophies.bronze
        game.earnedSilver = progress.earnedTrophies.silver
        game.earnedGold = progress.earnedTrophies.gold
        game.earnedPlatinum = progress.earnedTrophies.platinum
        game.lastUpdated = progress.lastUpdatedDateTime
        // The trophies match PSN again: the next sync has nothing to fetch for this game.
        game.detailsLastUpdated = progress.lastUpdatedDateTime
        try context.save()
        return newlyEarned.sorted { ($0.earnedAt ?? .distantPast) < ($1.earnedAt ?? .distantPast) }
    }

    // MARK: Sessions

    public func runningSession() throws -> PlaySessionRecord? {
        var descriptor = FetchDescriptor<PlaySessionRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func session(_ sessionId: String) throws -> PlaySessionRecord? {
        var descriptor = FetchDescriptor<PlaySessionRecord>(predicate: #Predicate { $0.sessionId == sessionId })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The finished sessions of a game (of every game for nil), the latest first.
    public func sessions(gameId: String? = nil, limit: Int? = nil) throws -> [PlaySessionRecord] {
        var descriptor: FetchDescriptor<PlaySessionRecord>
        if let gameId {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.gameId == gameId && $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        }
        if let limit { descriptor.fetchLimit = limit }
        return try context.fetch(descriptor)
    }

    /// Starts a session in a game; a session still running in another game ends first.
    public func startSession(gameId: String, at date: Date) throws -> PlaySessionRecord {
        if let running = try runningSession() {
            finish(running, at: date)
        }
        let game = try game(gameId)
        let session = PlaySessionRecord(
            sessionId: UUID().uuidString,
            gameId: gameId,
            gameName: game?.name ?? "",
            startedAt: date,
            startProgress: game?.progress ?? 0,
            startPlaySeconds: game?.playSeconds
        )
        // The goals the last session of this game did not reach carry over.
        if let previous = try sessions(gameId: gameId, limit: 1).first {
            session.goalTrophyIds = previous.goalTrophyIds.filter { id in
                !(game?.trophies.first { $0.trophyId == id }?.isEarned ?? true) && !previous.isGoalDone(id)
            }
        }
        context.insert(session)
        try context.save()
        return session
    }

    public func endSession(_ session: PlaySessionRecord, at date: Date) throws {
        finish(session, at: date)
        try context.save()
    }

    private func finish(_ session: PlaySessionRecord, at date: Date) {
        if let pausedAt = session.pausedAt {
            session.pausedSeconds += max(0, date.timeIntervalSince(pausedAt))
            session.pausedAt = nil
        }
        session.endedAt = date
        let game = try? self.game(session.gameId)
        session.endProgress = game?.progress
        session.endPlaySeconds = game?.playSeconds
    }

    public func pause(_ session: PlaySessionRecord, at date: Date) throws {
        guard session.pausedAt == nil, session.isRunning else { return }
        session.pausedAt = date
        try context.save()
    }

    public func resume(_ session: PlaySessionRecord, at date: Date) throws {
        guard let pausedAt = session.pausedAt else { return }
        session.pausedSeconds += max(0, date.timeIntervalSince(pausedAt))
        session.pausedAt = nil
        try context.save()
    }

    public func setGoals(_ trophyIds: [Int], for session: PlaySessionRecord) throws {
        var seen = Set<Int>()
        session.goalTrophyIds = trophyIds.filter { seen.insert($0).inserted }
        session.checkedGoalTrophyIds.removeAll { !session.goalTrophyIds.contains($0) }
        try context.save()
    }

    public func toggleGoal(_ trophyId: Int, in session: PlaySessionRecord) throws {
        if let index = session.checkedGoalTrophyIds.firstIndex(of: trophyId) {
            session.checkedGoalTrophyIds.remove(at: index)
        } else {
            session.checkedGoalTrophyIds.append(trophyId)
        }
        try context.save()
    }

    public func recordEarned(_ trophyIds: [Int], in session: PlaySessionRecord) throws {
        for id in trophyIds where !session.earnedTrophyIds.contains(id) {
            session.earnedTrophyIds.append(id)
        }
        try context.save()
    }

    public func setNote(_ text: String, for session: PlaySessionRecord) throws {
        session.note = text
        try context.save()
    }

    public func setSummary(_ summary: String, nextSteps: String?, for session: PlaySessionRecord) throws {
        session.summary = summary
        session.nextSteps = nextSteps
        try context.save()
    }

    // MARK: Notes

    public func note(gameId: String, trophyId: Int?) throws -> NoteRecord? {
        let trophy = trophyId ?? -1
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.gameId == gameId && $0.trophyId == trophy })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Writes a note; an empty text removes it.
    public func setNote(_ text: String, gameId: String, trophyId: Int?, at date: Date = Date()) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try note(gameId: gameId, trophyId: trophyId) {
            if trimmed.isEmpty {
                context.delete(existing)
            } else {
                existing.text = trimmed
                existing.updatedAt = date
            }
        } else if !trimmed.isEmpty {
            context.insert(NoteRecord(gameId: gameId, trophyId: trophyId, text: trimmed, updatedAt: date))
        }
        try context.save()
    }

    // MARK: Statistics

    /// Every earned trophy of the stored games.
    public func earnedTrophies() throws -> [EarnedTrophy] {
        let descriptor = FetchDescriptor<TrophyRecord>(predicate: #Predicate { $0.isEarned == true })
        let names = Dictionary(try games().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return try context.fetch(descriptor).compactMap { record in
            guard let earnedAt = record.earnedAt else { return nil }
            return EarnedTrophy(
                gameId: record.gameId, gameName: names[record.gameId] ?? "", trophyId: record.trophyId,
                name: record.name, type: record.type, earnedAt: earnedAt, earnedRate: record.earnedRate,
                iconURL: record.iconURL
            )
        }
    }
}
#endif
