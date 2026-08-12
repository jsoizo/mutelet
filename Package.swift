// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mutelet",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MuteletCore", targets: ["MuteletCore"]),
        .executable(name: "Mutelet", targets: ["Mutelet"]),
        .executable(name: "mutelet-probe", targets: ["MuteletProbe"]),
    ],
    targets: [
        .target(
            name: "MuteletCore",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        .executableTarget(
            name: "Mutelet",
            dependencies: ["MuteletCore"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(
            name: "MuteletProbe",
            dependencies: ["MuteletCore"]
        ),
        .testTarget(
            name: "MuteletCoreTests",
            dependencies: ["MuteletCore"],
            exclude: ["StatusOverlayControllerTests.swift"]
        ),
    ]
)
