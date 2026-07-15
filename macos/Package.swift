// Swift package manifest for the native HiBoss Island menu-bar app.
// Exports: HibossIsland executable and its test target.
// Dependencies: Apple SwiftUI, AppKit, Foundation, and Security frameworks only.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HibossIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HibossIsland", targets: ["HibossIsland"]),
    ],
    targets: [
        .executableTarget(name: "HibossIsland"),
        .testTarget(
            name: "HibossIslandTests",
            dependencies: ["HibossIsland"]
        ),
    ]
)
