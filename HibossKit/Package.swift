// Shared SwiftPM package for the HiBoss native clients (macOS + iOS).
// Exports: HibossKit — domain models, boss API client, option flow, keychain.
// Dependencies: Apple Foundation, Combine, and Security frameworks only.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HibossKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "HibossKit", targets: ["HibossKit"]),
    ],
    targets: [
        .target(name: "HibossKit"),
        .testTarget(name: "HibossKitTests", dependencies: ["HibossKit"]),
    ]
)
