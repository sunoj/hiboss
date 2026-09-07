// SwiftPM manifest for the isolated WKWebView renderer spike.
// Exports: PanelWebSpike executable.
// Dependencies: SwiftUI, AppKit, WebKit, and generated local resources.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelWebSpike",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PanelWebSpike", targets: ["PanelWebSpike"])],
    targets: [
        .executableTarget(
            name: "PanelWebSpike",
            path: ".",
            exclude: ["scripts", "dist"],
            sources: ["Sources/PanelWebApp"],
            resources: [.copy("Resources")]
        ),
    ]
)
