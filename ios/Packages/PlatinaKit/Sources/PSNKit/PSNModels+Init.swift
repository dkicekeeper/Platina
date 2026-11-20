import Foundation

// Public initialisers of PSN's models, for the store's tests, the core's tests and previews.
// PSN itself only ever decodes them.

public extension PSNProfile {
    init(onlineId: String, avatarURL: String? = nil, isPlus: Bool? = nil) {
        self.onlineId = onlineId
        self.avatars = avatarURL.map { [Avatar(size: "xl", url: $0)] }
        self.isPlus = isPlus
    }
}

public extension TitleTrophyLink {
    init(npTitleId: String, npCommunicationIds: [String]) {
        self.npTitleId = npTitleId
        self.trophyTitles = npCommunicationIds.map { List(npCommunicationId: $0) }
    }
}

