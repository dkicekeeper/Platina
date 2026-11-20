#if canImport(SwiftUI)
import SwiftUI

/// Platina's own colours, the one place they are written, for the app and its widgets: the
/// brand accent (DesignKitTheme.accent) and the four trophy metals. The metals are candidates
/// for DesignKit tokens (docs/PLAN.md §4).
public enum PlatinaPalette {
    /// Cool platinum blue, #3573BA: white text on it reads at 4.9:1.
    public static let accent = Color(red: 53 / 255, green: 115 / 255, blue: 186 / 255)

    public static let platinum = Color(red: 122 / 255, green: 160 / 255, blue: 196 / 255)
    public static let gold = Color(red: 214 / 255, green: 163 / 255, blue: 36 / 255)
    public static let silver = Color(red: 150 / 255, green: 158 / 255, blue: 168 / 255)
    public static let bronze = Color(red: 176 / 255, green: 112 / 255, blue: 64 / 255)

    /// A metal by its PSN name (`platinum`, `gold`, `silver`, `bronze`).
    public static func metal(_ type: String) -> Color {
        switch type {
        case "platinum": platinum
        case "gold": gold
        case "silver": silver
        default: bronze
        }
    }
}
#endif
