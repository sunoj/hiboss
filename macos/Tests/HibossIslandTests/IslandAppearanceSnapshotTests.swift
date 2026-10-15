// Captures the production Island panel under light and dark system appearances.
// Exports: IslandAppearanceSnapshotTests and a shared capture helper for Today snapshots.
// Dependencies: AppKit, XCTest, and the unchanged native Island controller/controls.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class IslandAppearanceSnapshotTests: XCTestCase {
    func testReferenceDecisionInBothAppearances() async throws {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let message = OptionMessage(id: "reference", body: "Which navigation should we ship?",
            agentName: "design",
            metadata: MessageMetadata(options: ["Sidebar", "Tabs"], optionDescriptions: [
                OptionDescription(label: "Sidebar", text: "Keep projects and sessions within easy reach."),
                OptionDescription(label: "Tabs", text: "Give the active workspace more room.")
            ], defaultOption: "Sidebar"),
            expiresAt: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(300)),
            sessionLabel: "mac-client", sessionBranch: "ui-v4")
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == message.id }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try await Self.capture(flow: flow, appearance: appearance, name: "island-reference")
        }
    }

    func testThreeImageOptionsWithDescriptionInBothAppearances() async throws {
        let options = ["Coast", "Forest", "Mountains"]
        let server = HistorySnapshotMediaServer()
        try await server.start()
        defer { server.stop() }
        let media = options.enumerated().map { index, label in
            OptionMedia(label: label, url: server.baseURL + (index == 1 ? "/hold.png" : "/ship.png"))
        }
        let message = OptionMessage(id: "image-descriptions", body: "Choose a destination",
            metadata: MessageMetadata(options: options, optionMedia: media, optionDescriptions: [
                OptionDescription(label: "Coast", text: "A quiet break by the water.")
            ]))
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == message.id }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try await Self.capture(flow: flow, appearance: appearance, name: "image-descriptions")
        }
    }

    func testPlainOptionsInBothAppearances() async throws {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let message = OptionMessage(id: "plain-options", body: "Choose a destination",
            metadata: MessageMetadata(options: ["Coast", "Forest", "Mountains"]))
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        defer { flow.disconnect() }
        try await waitForCondition { flow.activeMessage?.id == message.id }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try await Self.capture(flow: flow, appearance: appearance, name: "plain-options")
        }
    }

    static func capture(flow: OptionFlowStore, appearance: NSAppearance.Name, name: String) async throws {
        _ = NSApplication.shared
        let original = NSApp.appearance
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = original }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "IslandAppearanceSnapshotTests"))
        defer { defaults.removePersistentDomain(forName: "IslandAppearanceSnapshotTests") }
        let settings = AppSettings(defaults: defaults, keychain: SnapshotTokenStore())
        settings.playsSound = false
        let screen = try XCTUnwrap(NSScreen.main)
        let geometry = IslandGeometry(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            safeAreaTop: 32)
        let controller = IslandPanelController(flow: flow, settings: settings,
            overview: islandTestOverview(flow: flow), screens: { [geometry] })
        defer {
            controller.panel.orderOut(nil)
            controller.optionWindow.orderOut(nil)
        }
        try await Task.sleep(for: .milliseconds(750))
        let host = try XCTUnwrap(controller.panel.contentView)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(controller.panel.isVisible)
        XCTAssertEqual(editors(host).count, 1)
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let label = appearance == .aqua ? "light" : "dark"
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(controller.panel.windowNumber),
            url.appendingPathComponent("\(name)-\(label).png").path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name)-\(label)-bitmap.png"))
    }

    private static func editors(_ view: NSView) -> [NSTextField] {
        view.subviews.flatMap { child in
            if let field = child as? NSTextField, field.isEditable { return [field] }
            return editors(child)
        }
    }
}

private struct SnapshotTokenStore: TokenStoring {
    func read() throws -> String? { nil }
    func write(_ token: String) throws {}
}
