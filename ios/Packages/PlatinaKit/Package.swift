// swift-tools-version: 6.0
import PackageDescription

// PlatinaKit: the app's code that needs no UI.
// - PSNKit: the only door to the PlayStation Network (docs/PLAN.md §2): sign-in, tokens, the API
//   client and its models.
// - PlatinaCore: the logic over them: what a sync fetches, time played, statistics, the
//   library's filters.
// - PlatinaStore: the SwiftData store and the sync that fills it (Apple platforms only; on
//   Linux its files compile to nothing).
// PSNKit and PlatinaCore depend on Foundation alone, so their tests also run on Linux
// (`swift test` in this folder).
let package = Package(
    name: "PlatinaKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "PSNKit", targets: ["PSNKit"]),
        .library(name: "PlatinaCore", targets: ["PlatinaCore"]),
        .library(name: "PlatinaStore", targets: ["PlatinaStore"]),
    ],
    targets: [
        .target(name: "PSNKit"),
        .target(name: "PlatinaCore", dependencies: ["PSNKit"]),
        .target(name: "PlatinaStore", dependencies: ["PSNKit", "PlatinaCore"]),
        .testTarget(
            name: "PSNKitTests",
            dependencies: ["PSNKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PlatinaCoreTests", dependencies: ["PlatinaCore", "PSNKit"]),
        .testTarget(
            name: "PlatinaStoreTests",
            dependencies: ["PlatinaStore", "PlatinaCore", "PSNKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
