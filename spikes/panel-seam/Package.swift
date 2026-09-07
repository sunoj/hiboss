// Swift package manifest for the native/web seam spike.
// Exports: PanelSeamSpike executable.
// Dependencies: SwiftUI, AppKit, WebKit, and bundled local resources.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelSeamSpike",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PanelSeamSpike", targets: ["PanelSeamSpike"])],
    targets: [
        .executableTarget(
            name: "PanelSeamSpike",
            path: ".",
            exclude: ["scripts", "dist", "web", "evidence"],
            sources: ["Sources/PanelSeamSpike"],
            resources: [.copy("Resources")]
        ),
    ]
)
