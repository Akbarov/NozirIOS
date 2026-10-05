// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NozirKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NozirAppFeature", targets: ["NozirAppFeature"]),
    ],
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirL10n"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirDesignSystem"),
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n"]
        ),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirConfigTests", dependencies: ["NozirConfig", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirDesignSystemTests", dependencies: ["NozirDesignSystem"]),
        .testTarget(name: "NozirL10nTests", dependencies: ["NozirL10n"]),
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n"]
        ),
    ]
)
