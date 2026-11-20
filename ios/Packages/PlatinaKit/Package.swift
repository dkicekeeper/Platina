// swift-tools-version: 6.0
import PackageDescription

// PlatinaKit: the app's code that needs no UI. PSNKit is the only door to the PlayStation
// Network (docs/PLAN.md §2): sign-in, tokens, the API client and its models. It depends on
// Foundation alone, so its tests also run on Linux (`swift test` in this folder).
let package = Package(
    name: "PlatinaKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "PSNKit", targets: ["PSNKit"]),
    ],
    targets: [
        .target(name: "PSNKit"),
        .testTarget(
            name: "PSNKitTests",
            dependencies: ["PSNKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
