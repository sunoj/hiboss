// Swift package manifest for the native HiBoss Island menu-bar app.
// Exports: HibossIsland executable and its test target.
// Dependencies: HibossKit shared package plus SwiftUI, AppKit, and Security.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HibossIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HibossIsland", targets: ["HibossIsland"]),
    ],
    dependencies: [
        .package(path: "../HibossKit"),
    ],
    targets: [
        .executableTarget(
            name: "HibossIsland",
            dependencies: [.product(name: "HibossKit", package: "HibossKit")]
        ),
        .testTarget(
            name: "HibossIslandTests",
            dependencies: ["HibossIsland", .product(name: "HibossKit", package: "HibossKit")]
        ),
    ]
)
