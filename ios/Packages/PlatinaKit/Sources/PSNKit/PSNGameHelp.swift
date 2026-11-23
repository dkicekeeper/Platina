import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Game Help: PlayStation's own tips for PS5 trophies, text and video, free for every player
// since 2024. Two GraphQL operations the PlayStation App sends as persisted queries
// (andshrew/PlayStation-Trophies, docs/APIv2.md, "Game Help Endpoints"). The hashes are the
// app's: when Sony changes them, the answer is an error and the help goes quiet, nothing else.

/// A trophy that has Game Help, and the ids to ask for it with.
public struct GameHelpHint: Decodable, Sendable, Hashable {
    public init(trophyId: String, udsObjectId: String, helpType: String) {
        self.trophyId = trophyId
        self.udsObjectId = udsObjectId
        self.helpType = helpType
    }

    /// The trophy's id as text (`"18"`).
    public let trophyId: String
    /// The help's own id (`"GATCHA_SECRET"`).
    public let udsObjectId: String
    /// `HINT` so far.
    public let helpType: String

    public var trophyNumber: Int? { Int(trophyId) }
}

/// One piece of a trophy's Game Help: a step with its words and, mostly, a video.
public struct GameHelpTip: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let text: String?
    /// An HLS stream with a short-lived token: play it soon after asking.
    public let videoURL: URL?
}

/// A trophy's Game Help.
public struct GameHelp: Sendable, Hashable {
    public let trophyId: Int
    public let tips: [GameHelpTip]
}

// MARK: - Requests

extension PSNClient {
    static let gameHelpHeaders = [
        "apollographql-client-name": "PlayStationApp-Android",
        "content-type": "application/json",
    ]
    static let hintAvailabilityHash = "71bf26729f2634f4d8cca32ff73aaf42b3b76ad1d2f63b490a809b66483ea5a7"
    static let tipsHash = "93768752a9f4ef69922a543e2209d45020784d8781f57b37a5294e6e206c5630"

    /// The trophies of a list that have Game Help. One request.
    public func gameHelpHints(npCommunicationId: String) async throws -> [GameHelpHint] {
        let data: HintAvailabilityData = try await graphQL(
            "metGetHintAvailability",
            variables: HintVariables(npCommId: npCommunicationId),
            hash: Self.hintAvailabilityHash
        )
        return data.hintAvailabilityRetrieve?.trophies ?? []
    }

    /// The Game Help of these trophies of a list, in one request.
    public func gameHelp(npCommunicationId: String, hints: [GameHelpHint]) async throws -> [GameHelp] {
        guard !hints.isEmpty else { return [] }
        let data: TipsData = try await graphQL(
            "metGetTips",
            variables: TipsVariables(npCommId: npCommunicationId, trophies: hints.map {
                .init(trophyId: $0.trophyId, udsObjectId: $0.udsObjectId, helpType: $0.helpType)
            }),
            hash: Self.tipsHash
        )
        return (data.tipsRetrieve?.trophies ?? []).compactMap { trophy in
            guard let id = Int(trophy.trophyId) else { return nil }
            let tips = (trophy.groups ?? []).flatMap { $0.tipContents ?? [] }.map { content in
                GameHelpTip(
                    id: content.tipId ?? UUID().uuidString,
                    title: content.displayName?.trimmedOrNil,
                    text: content.description?.trimmedOrNil,
                    videoURL: content.mediaType == "VIDEO" ? PSNImageURL.from(content.mediaUrl) : nil
                )
            }
            return GameHelp(trophyId: id, tips: tips)
        }
    }

    private func graphQL<Variables: Encodable, Answer: Decodable>(
        _ operation: String,
        variables: Variables,
        hash: String
    ) async throws -> Answer {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let variablesText = String(decoding: try encoder.encode(variables), as: UTF8.self)
        let extensionsText = String(decoding: try encoder.encode(Extensions(persistedQuery: .init(sha256Hash: hash))), as: UTF8.self)
        let response: GraphQLResponse<Answer> = try await get(
            "graphql/v1/op",
            query: [
                URLQueryItem(name: "operationName", value: operation),
                URLQueryItem(name: "variables", value: variablesText),
                URLQueryItem(name: "extensions", value: extensionsText),
            ],
            headers: Self.gameHelpHeaders
        )
        guard let data = response.data else {
            let message = response.errors?.compactMap(\.message).joined(separator: "; ") ?? "no data"
            PSNLog.failure("GraphQL \(operation): \(message)")
            throw PSNError.decoding("GraphQL \(operation): \(message)")
        }
        return data
    }
}

// MARK: - Wire format

struct GraphQLResponse<Answer: Decodable>: Decodable {
    struct Failure: Decodable {
        let message: String?
    }

    let data: Answer?
    let errors: [Failure]?
}

private struct Extensions: Encodable {
    struct PersistedQuery: Encodable {
        var version = 1
        let sha256Hash: String
    }

    let persistedQuery: PersistedQuery
}

private struct HintVariables: Encodable {
    let npCommId: String
}

private struct TipsVariables: Encodable {
    struct Trophy: Encodable {
        let trophyId: String
        let udsObjectId: String
        let helpType: String
    }

    let npCommId: String
    let trophies: [Trophy]
}

struct HintAvailabilityData: Decodable {
    struct Availability: Decodable {
        let trophies: [GameHelpHint]?
    }

    let hintAvailabilityRetrieve: Availability?
}

struct TipsData: Decodable {
    struct Tips: Decodable {
        let hasAccess: Bool?
        let trophies: [TrophyTip]?
    }

    struct TrophyTip: Decodable {
        let trophyId: String
        let groups: [Group]?
    }

    struct Group: Decodable {
        let tipContents: [Content]?
    }

    struct Content: Decodable {
        let tipId: String?
        let displayName: String?
        let description: String?
        let mediaType: String?
        let mediaUrl: String?
    }

    let tipsRetrieve: Tips?
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
