import PlatinaAssistant

/// Whether Plati can work here (docs/assistant.md §7): the build knows its server, and the device
/// signs requests with App Attest (the Simulator with the dev token in Debug). Without a signature
/// the server answers only for what is already built (a guide, a walkthrough's chapters): it
/// writes nothing new.
enum PlatiAvailability: Equatable {
    case available
    /// No server host in this build (a developer's own build without `PLATINA_ASSISTANT_HOST`).
    case notConfigured
    /// No App Attest on this device, as on a Mac running the iPad app.
    case unsupportedDevice

    static let current: PlatiAvailability = {
        // The screenshots' Plati answers from a script on the device.
        if ScreenshotDemo.isOn { return .available }
        guard AssistantConfig.serverURL != nil else { return .notConfigured }
        guard AssistantAttestation.isSupported || AssistantConfig.devToken != nil else { return .unsupportedDevice }
        return .available
    }()

    /// Plati can write: talk, build guides, walkthroughs and their chapters.
    var canWrite: Bool { self == .available }

    /// Why Plati is not here, where it would be.
    var message: String {
        switch self {
        case .unsupportedDevice: String(localized: "plati.unsupported.message")
        case .available, .notConfigured: String(localized: "plati.offline.message")
        }
    }
}
