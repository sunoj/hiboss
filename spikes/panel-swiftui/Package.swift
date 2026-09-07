// Swift package manifest for the throwaway native panel adapter.
// Exports: PanelSwiftUISpike executable.
// Dependencies: Apple SwiftUI, AppKit, Charts, Combine, and Foundation.

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PanelSwiftUISpike",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PanelSwiftUISpike", targets: ["PanelSwiftUISpike"])],
    targets: [.executableTarget(name: "PanelSwiftUISpike")]
)
