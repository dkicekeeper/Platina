import Foundation

/// What the person chose in Settings about spoilers, on this device: the screens read it with
/// `@AppStorage` and these keys, Plati's tools and its `<app_context>` read it here. Off by
/// default: hidden trophies and spoiler steps wait for a tap.
public enum DisplaySettings {
    /// Hidden trophies show their names and descriptions at once.
    public static let hiddenTrophiesKey = "settings.showHiddenTrophies"
    /// The walkthrough's spoiler steps show at once.
    public static let spoilersKey = "settings.showSpoilers"

    public static var showsHiddenTrophies: Bool { UserDefaults.standard.bool(forKey: hiddenTrophiesKey) }
    public static var showsSpoilers: Bool { UserDefaults.standard.bool(forKey: spoilersKey) }
}
