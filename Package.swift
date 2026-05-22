// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AnySee",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AnySee", targets: ["AnySee"]),
        .executable(name: "anysee", targets: ["AnySeeCLI"]),
        .library(name: "AnySeeCore", targets: ["AnySeeCore"])
    ],
    targets: [
        .target(
            name: "AnySeeCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "AnySee",
            dependencies: ["AnySeeCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "AnySeeCLI",
            dependencies: ["AnySeeCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "AnySeeCoreTests",
            dependencies: ["AnySeeCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
