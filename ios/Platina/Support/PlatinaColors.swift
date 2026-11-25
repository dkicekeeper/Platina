import SwiftUI
import PSNKit
import PlatinaShared

/// The app's own colours. Everything else is DesignKit's tokens.
enum PlatinaColors {
    /// Plasma, #D6006F in light mode and #FF4FA0 in dark (PlatinaPalette). The asset catalog's
    /// AccentColor is the same pair (system chrome reads that one).
    static let accent = PlatinaPalette.accent
}

/// The colours of the four trophy metals (PlatinaPalette, shared with the widgets).
extension TrophyType {
    var color: Color { PlatinaPalette.metal(rawValue) }

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
        case .offline:
            String(localized: "error.offline")
        case .transport:
            String(localized: "error.psnUnreachable")
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
