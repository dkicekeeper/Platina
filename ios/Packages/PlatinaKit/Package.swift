// swift-tools-version: 6.0
import PackageDescription

// PlatinaKit: the app's code that needs no UI.
// - PSNKit: the only door to the PlayStation Network (docs/domains/psn.md): sign-in, tokens, the API
//   client and its models.
// - PlatinaCore: the logic over them: what a sync fetches, time played, statistics, the
//   library's filters.
// - PlatinaStore: the SwiftData store and the sync that fills it (Apple platforms only; on
//   Linux its files compile to nothing).
// - PlatinaShared: what the app and its widget extension share.
// - PlatinaAssistant: Plati's client (docs/assistant.md).
// PSNKit and PlatinaCore depend on Foundation alone, so their tests also run on Linux
// (`swift test` in this folder).
let package = Package(
    name: "PlatinaKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "PSNKit", targets: ["PSNKit"]),
        .library(name: "PlatinaCore", targets: ["PlatinaCore"]),
        .library(name: "PlatinaStore", targets: ["PlatinaStore"]),
        .library(name: "PlatinaShared", targets: ["PlatinaShared"]),
        .library(name: "PlatinaAssistant", targets: ["PlatinaAssistant"]),
    ],
    targets: [
        .target(name: "PSNKit"),
        .target(name: "PlatinaCore", dependencies: ["PSNKit"]),
        .target(name: "PlatinaStore", dependencies: ["PSNKit", "PlatinaCore", "PlatinaAssistant"]),
        // Shared by the app and its widget extension: the Live Activity's attributes, the widgets'
        // snapshot. Foundation only (ActivityKit parts behind canImport).
        .target(name: "PlatinaShared"),
        // Plati's client: the wire format, the conversation loop, the server client, App Attest
        // (docs/assistant.md). Foundation only, so its tests run on Linux too.
        .target(name: "PlatinaAssistant"),
        .testTarget(
            name: "PSNKitTests",
            dependencies: ["PSNKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PlatinaCoreTests", dependencies: ["PlatinaCore", "PSNKit"]),
        .testTarget(name: "PlatinaAssistantTests", dependencies: ["PlatinaAssistant"]),
        .testTarget(name: "PlatinaSharedTests", dependencies: ["PlatinaShared"]),
        .testTarget(
            name: "PlatinaStoreTests",
            dependencies: ["PlatinaStore", "PlatinaCore", "PSNKit", "PlatinaAssistant"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
