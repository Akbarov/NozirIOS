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
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking"]),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
    ]
)
