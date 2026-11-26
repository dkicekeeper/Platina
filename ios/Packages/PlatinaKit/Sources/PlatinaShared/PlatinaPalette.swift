#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Platina's own colours, the one place they are written, for the app and its widgets: the
/// brand accent (DesignKitTheme.accent) and the four trophy metals. The metals are candidates
/// for DesignKit tokens (docs/domains/design.md).
public enum PlatinaPalette {
    /// Plasma, the owner's choice (2026-11-25, over the platinum blue #3573BA): a deep magenta in
    /// light mode, #D6006F (5.1:1 on white, 4.6:1 on a grey card), a brighter one in dark mode,
    /// #FF4FA0 (6.9:1 on black, 5.6:1 on a dark card). Tenra is indigo, Dalada green, Platina
    /// magenta: the three apps tell apart at a glance.
    public static let accent: Color = {
        #if canImport(UIKit)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1, green: 79 / 255, blue: 160 / 255, alpha: 1)
                : UIColor(red: 214 / 255, green: 0, blue: 111 / 255, alpha: 1)
        })
        #else
        Color(red: 214 / 255, green: 0, blue: 111 / 255)
        #endif
    }()

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
