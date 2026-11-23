import Foundation
import Testing
@testable import PSNKit

@Suite("Dates and durations")
struct DateAndDurationTests {
    @Test("Dates with any fraction of a second, or none")
    func dates() throws {
        let plain = try #require(PSNDate.parse("2015-07-10T19:40:19Z"))
        #expect(plain == Date(timeIntervalSince1970: 1_436_557_219))

        let twoDigits = try #require(PSNDate.parse("2024-08-03T19:28:27.12Z"))
        let whole = try #require(PSNDate.parse("2024-08-03T19:28:27Z"))
        #expect(abs(twoDigits.timeIntervalSince(whole) - 0.12) < 0.0001)

        let withOffset = try #require(PSNDate.parse("2023-01-05T13:00:00.000+03:00"))
        #expect(withOffset == PSNDate.parse("2023-01-05T10:00:00Z"))

        #expect(PSNDate.parse("yesterday") == nil)
    }

    @Test("Time played", arguments: [
        ("PT228H56M33S", 824_193.0),  // 228 h 56 min 33 s
        ("PT45M", 2_700.0),
        ("PT0S", 0.0),
        ("P1DT2H", 93_600.0),
        ("PT1.5S", 1.5),
    ])
    func durations(_ input: String, _ seconds: Double) {
        #expect(PSNDuration.parse(input) == seconds)
    }

    @Test("Not a duration", arguments: ["", "P", "PT", "228H", "PT5X", "PT5"])
    func invalidDurations(_ input: String) {
        #expect(PSNDuration.parse(input) == nil)
    }
}

@Suite("Models")
struct ModelTests {
    @Test("A trophy list")
    func trophyTitle() throws {
        let page = try JSONDecoder.psn.decode(TrophyTitlesPage.self, from: Fixture.data("trophyTitles-page1"))
        #expect(page.nextOffset == 2)
        let lamb = page.trophyTitles[0]
        #expect(lamb.id == "NPWR28536_00")
        #expect(lamb.isPS5)
        #expect(lamb.npServiceName == "trophy2")
        #expect(lamb.definedTrophies.total == 57)
        #expect(lamb.earnedTrophies[.gold] == 2)
        #expect(!lamb.isPlatinumEarned)
        #expect(!lamb.isCompleted)

        let bloodborne = page.trophyTitles[1]
        #expect(!bloodborne.isPS5)
        #expect(bloodborne.isPlatinumEarned)
        #expect(bloodborne.isCompleted)
    }

    @Test("An empty icon is no icon")
    func emptyIcon() throws {
        let page = try JSONDecoder.psn.decode(TrophyTitlesPage.self, from: Fixture.data("trophyTitles-page2"))
        #expect(page.trophyTitles[0].iconURL == nil)
        #expect(page.nextOffset == nil)
    }

    @Test("Definitions and earnings become trophies")
    func merge() throws {
        let definitions = try JSONDecoder.psn.decode(TrophyDefinitionsPage.self, from: Fixture.data("titleTrophies"))
        let earnings = try JSONDecoder.psn.decode(TrophyEarningsPage.self, from: Fixture.data("earnedTrophies"))
        let trophies = PSNClient.merge(definitions: definitions.trophies, earnings: earnings.trophies)

        #expect(trophies.count == 3)
        let platinum = trophies[0]
        #expect(platinum.type == .platinum)
        #expect(!platinum.isEarned)
        #expect(platinum.rarity == .ultraRare)
        #expect(platinum.earnedRate == 1.8)
        #expect(platinum.progress == nil)

        let dice = trophies[1]
        #expect(dice.progress?.current == 3)
        #expect(dice.progress?.target == 4)
        #expect(dice.progress?.fraction == 0.75)

        let dlc = trophies[2]
        #expect(dlc.groupId == "003")
        #expect(dlc.isHidden)
        #expect(dlc.isEarned)
        #expect(dlc.earnedAt == PSNDate.parse("2026-11-18T21:14:03Z"))
    }

    @Test("Profile, summary, games, presence")
    func profileAndGames() throws {
        let summary = try JSONDecoder.psn.decode(TrophySummary.self, from: Fixture.data("trophySummary"))
        #expect(summary.level == 412)
        #expect(summary.earnedTrophies.platinum == 41)

        let profile = try JSONDecoder.psn.decode(PSNProfile.self, from: Fixture.data("profile"))
        #expect(profile.onlineId == "trophy_hunter")
        #expect(profile.avatarURL?.absoluteString.hasSuffix("avatar_xl.png") == true)

        let games = try JSONDecoder.psn.decode(PlayedGamesPage.self, from: Fixture.data("playedGames"))
        let lamb = try #require(games.titles.first)
        #expect(lamb.timePlayed == TimeInterval(137_525))  // 38 h 12 min 5 s
        #expect(lamb.imageURL?.absoluteString.hasSuffix("cotl-ru.png") == true)

        let presence = try JSONDecoder.psn.decode(PresenceResponse.self, from: Fixture.data("presence")).presence
        #expect(presence.onlineStatus == "online")
        #expect(presence.runningGame?.npTitleId == "PPSA03224_00")

        let links = try JSONDecoder.psn.decode(TitleTrophyLinksResponse.self, from: Fixture.data("trophyLinks"))
        #expect(links.titles.first?.trophyTitles.first?.npCommunicationId == "NPWR28536_00")
    }

    @Test("The trophy level reads as a number, as PSN sends it, and as text, as psn-api has it")
    func trophyLevelAsTextOrNumber() throws {
        let text = #"{"accountId":"1","trophyLevel":"38","progress":5,"tier":1,"earnedTrophies":{"bronze":1,"silver":0,"gold":0,"platinum":0}}"#
        #expect(try JSONDecoder.psn.decode(TrophySummary.self, from: Data(text.utf8)).level == 38)
        let number = #"{"accountId":"1","trophyLevel":437,"progress":5,"tier":1,"earnedTrophies":{"bronze":1,"silver":0,"gold":0,"platinum":0}}"#
        #expect(try JSONDecoder.psn.decode(TrophySummary.self, from: Data(number.utf8)).level == 437)
    }

    @Test("Picture links go over https: iOS does not load PSN's http avatars")
    func imageURLs() {
        #expect(PSNImageURL.from("http://psn-rsc.prod.dl.playstation.net/psn-rsc/avatar/a_xl.png")?.absoluteString
            == "https://psn-rsc.prod.dl.playstation.net/psn-rsc/avatar/a_xl.png")
        #expect(PSNImageURL.from("https://image.api.playstation.com/trophy/np/x.png")?.absoluteString
            == "https://image.api.playstation.com/trophy/np/x.png")
        #expect(PSNImageURL.from(nil) == nil)
        #expect(PSNImageURL.from("") == nil)
    }

    @Test("Trophy types sort platinum first")
    func typeOrder() {
        #expect([TrophyType.bronze, .platinum, .silver, .gold].sorted() == [.platinum, .gold, .silver, .bronze])
    }
}
