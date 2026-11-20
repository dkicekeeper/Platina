import SwiftUI
import PSNKit

/// The app's own colours. Everything else is DesignKit's tokens.
enum PlatinaColors {
    /// Cool platinum blue, #3573BA: white text on it reads at 4.9:1. The asset catalog's
    /// AccentColor is the same colour (system chrome reads that one).
    static let accent = Color(red: 53 / 255, green: 115 / 255, blue: 186 / 255)
}

/// The colours of the four trophy metals. A candidate for DesignKit tokens (docs/PLAN.md §4);
/// until then they live only here.
extension TrophyType {
    var color: Color {
        switch self {
        case .platinum: Color(red: 122 / 255, green: 160 / 255, blue: 196 / 255)
        case .gold: Color(red: 214 / 255, green: 163 / 255, blue: 36 / 255)
        case .silver: Color(red: 150 / 255, green: 158 / 255, blue: 168 / 255)
        case .bronze: Color(red: 176 / 255, green: 112 / 255, blue: 64 / 255)
        }
    }

    var systemImage: String { "trophy.fill" }

    var title: String {
        switch self {
        case .platinum: String(localized: "trophy.type.platinum")
        case .gold: String(localized: "trophy.type.gold")
        case .silver: String(localized: "trophy.type.silver")
        case .bronze: String(localized: "trophy.type.bronze")
        }
    }
}

extension TrophyRarity {
    var title: String {
        switch self {
        case .ultraRare: String(localized: "trophy.rarity.ultraRare")
        case .veryRare: String(localized: "trophy.rarity.veryRare")
        case .rare: String(localized: "trophy.rarity.rare")
        case .common: String(localized: "trophy.rarity.common")
        }
    }
}

extension PSNError {
    /// What to tell the person.
    var userMessage: String {
        switch self {
        case .notSignedIn, .sessionExpired:
            String(localized: "error.sessionExpired")
        case .invalidNPSSO:
            String(localized: "error.invalidNPSSO")
        case .authorizationFailed:
            String(localized: "error.signInFailed")
        case .rateLimited:
            String(localized: "error.rateLimited")
        case .transport:
            String(localized: "error.offline")
        case .http, .decoding:
            String(localized: "error.psnUnavailable")
        }
    }
}

extension Error {
    var userMessage: String {
        (self as? PSNError)?.userMessage ?? String(localized: "error.psnUnavailable")
    }
}
