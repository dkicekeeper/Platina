import Foundation
import Testing
@testable import PSNKit

/// The screenshots' made-up library (`PSNDemo`) is read by the real client, as a real account is.
@Suite("Demo library")
struct DemoTests {
    let now = Date(timeIntervalSince1970: 1_795_000_000)

    @Test("The client is signed in and reads every game, its trophies and groups, in Russian")
    func library() async throws {
        let client = PSNDemo.client(language: "ru-RU", now: now)
        #expect(await client.isSignedIn)

        let titles = try await client.trophyTitles()
        #expect(titles.count == 8)
        let ember = try #require(titles.first { $0.trophyTitleName.hasPrefix("Emberfall") })
        #expect(ember.iconURL?.absoluteString == "demo://art/emberfall/icon")
        #expect(ember.progress > 50 && ember.progress < 100)
        #expect(!ember.isPlatinumEarned)
        #expect(titles.filter(\.isPlatinumEarned).count == 3)

        let trophies = try await client.trophies(for: ember)
        #expect(trophies.count == 23)
        #expect(trophies.first?.name == "Последняя корона")
        let collector = try #require(trophies.first { $0.id == 8 })
        #expect(collector.progress?.current == 31 && collector.progress?.target == 40)
        #expect(trophies.first { $0.id == 10 }?.isHidden == true)
        #expect(trophies.filter(\.isEarned).count == 17)
        #expect(trophies.allSatisfy { $0.iconURL?.scheme == "demo" })

        let groups = try await client.trophyGroups(for: ember)
        #expect(groups.map(\.id) == ["default", "001"])
        #expect(groups.last?.trophyGroupName == "Приливы пепла")

        let progress = try await client.progress(for: ember)
        #expect(progress.progress == ember.progress)
    }

    @Test("English names for an English client")
    func english() async throws {
        let client = PSNDemo.client(language: "en-US", now: now)
        let ember = try #require(try await client.trophyTitles().first { $0.trophyTitleName.hasPrefix("Emberfall") })
        let trophies = try await client.trophies(for: ember)
        #expect(trophies.first?.name == "The Last Crown")
        #expect(try await client.trophyGroups(for: ember).last?.trophyGroupName == "Tides of Ash")
    }

    @Test("Played games carry time and art, link to their trophy lists; the profile and summary read")
    func gamesAndProfile() async throws {
        let client = PSNDemo.client(language: "ru-RU", now: now)
        let played = try await client.playedGames()
        #expect(played.count == 8)
        let ember = try #require(played.first { $0.name.hasPrefix("Emberfall") })
        #expect(ember.keyArtURL?.absoluteString == "demo://art/emberfall/hub")
        #expect(ember.logoURL?.absoluteString == "demo://art/emberfall/logo")
        #expect(abs((ember.timePlayed ?? 0) - 46.3 * 3600) < 60)

        let links = try await client.trophyLinks(forTitleIds: played.map(\.titleId))
        #expect(links.count == 8)

        let summary = try await client.trophySummary()
        #expect(summary.accountId == PSNDemo.accountId)
        #expect(summary.earnedTrophies.platinum > 3)
        #expect(try await client.profile().onlineId == PSNDemo.onlineId)
    }

    @Test("Earned dates lie in the past, the newest today")
    func dates() async throws {
        let client = PSNDemo.client(language: "ru-RU", now: now)
        for title in try await client.trophyTitles() {
            let earned = try await client.trophies(for: title).compactMap(\.earnedAt)
            #expect(earned.allSatisfy { $0 <= now })
        }
        let ember = try #require(try await client.trophyTitles().first { $0.trophyTitleName.hasPrefix("Emberfall") })
        let newest = try await client.trophies(for: ember).compactMap(\.earnedAt).max()
        #expect(newest.map { now.timeIntervalSince($0) < 24 * 3600 } == true)
    }

    @Test("Anything else is not found")
    func unknown() async throws {
        let transport = PSNDemoTransport(library: PSNDemo.Library(now: now))
        let request = URLRequest(url: URL(string: "https://m.np.playstation.com/api/graphql/v1/op")!)
        let (_, response) = try await transport.send(request, followRedirects: true)
        #expect(response.statusCode == 404)
    }
}
