// Hosts actual native windows for Today, all-clear, sidebar destinations, and notch Island.
// Exports: TodaySnapshotTests; HIBOSS_V4_SNAPSHOTS writes light/dark PNG evidence.
// Dependencies: AppKit, SwiftUI, HibossKit, and the production MainView/IslandView.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class TodaySnapshotTests: XCTestCase {
    func testTodayAndAllClearInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for clear in [false, true] {
                let name = "today-\(clear ? "all-clear" : "decisions")-\(label(scheme))"
                let flow = OptionFlowStore()
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: flow,
                    previewHistory: clear ? [] : fixtures())
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = makeWindow(host, size: NSSize(width: 1320, height: 820), scheme: scheme)
                defer { window.close() }
                try await waitForCondition {
                    self.descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
                        .count >= (clear ? 1 : 2)
                }
                try await Task.sleep(for: .milliseconds(250))
                host.layoutSubtreeIfNeeded()
                let scenes = descendants(host).compactMap { $0 as? NSImageView }
                XCTAssertEqual(scenes.count, clear ? 1 : 0,
                    "The all-clear scene must be mounted only when clear")
                for scene in scenes {
                    let frame = scene.convert(scene.bounds, to: host)
                    XCTAssertGreaterThan(frame.width, 100)
                    XCTAssertEqual(frame.height, 220, accuracy: 1)
                    XCTAssertTrue(host.bounds.contains(frame), "Scene frame: \(frame), host: \(host.bounds)")
                    let scroll = try XCTUnwrap(scene.enclosingScrollView)
                    let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: host)
                    XCTAssertTrue(viewport.contains(frame), "The vector must fit the visible Today viewport")
                }
                let editors = descendants(host).compactMap { $0 as? NSTextField }.filter(\.isEditable)
                XCTAssertGreaterThanOrEqual(editors.count, clear ? 1 : 2,
                    "Session search and a selected decision's reply editor are native fields")
                for editor in editors {
                    XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1)
                        .contains(editor.convert(editor.bounds, to: host)))
                }
                try await write(host, name: name)
            }
        }
    }

    func testIslandShowsOneSharedDecisionInBothAppearances() async throws {
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        let history = fixtures()
        let requiredInput = try XCTUnwrap(AttentionModel.items(from: history, now: .now).first)
        flow.connect(api: ScriptedBossAPI(messages: [requiredInput.asOptionMessage], history: history))
        defer { flow.disconnect() }
        try await waitForCondition { flow.historyState == .loaded && flow.activeMessage != nil }
        let presentation = try XCTUnwrap(IslandAttention.presentation(live: nil,
            history: flow.historyMessages, now: .now))
        XCTAssertEqual(presentation.message.id, "deploy")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try await IslandAppearanceSnapshotTests.capture(
                flow: flow, appearance: appearance, name: "island")
        }
    }

    func testMenuBarLabelInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 70, height: 24))
            button.isBordered = false
            AppIdentity.configure(button, count: 2)
            let window = NSWindow(contentRect: button.frame,
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            window.contentView = button
            window.orderFront(nil)
            defer { window.close() }
            try await write(button, name: "menu-bar-\(label(scheme))", minimumWidth: 60)
        }
    }

    func testExistingDestinationsRemainHostedBehindTheSidebar() async throws {
        let attachmentServer = HistorySnapshotMediaServer()
        defer { attachmentServer.stop() }
        try await attachmentServer.start()
        let history = PhaseBSnapshotFixtures.history(baseURL: attachmentServer.baseURL)
        let boxAPI = ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData())
        let panels = PanelsModel(demoMode: true, autoload: false)
        for scheme in [ColorScheme.light, .dark] {
            for (name, destination) in [("session", OverviewDestination.session("hiboss")),
                                        ("box", .box), ("progress", .progress)] {
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                    initialDestination: destination, previewHistory: history,
                    previewSessions: PhaseBSnapshotFixtures.inventory,
                    boxProvider: { boxAPI }, panelsModel: panels)
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = makeWindow(host, size: NSSize(width: 1320, height: 1060), scheme: scheme)
                defer { window.close() }
                try await waitForCondition {
                    self.descendants(host).compactMap { $0 as? NSTextField }.contains { $0.isEditable }
                }
                try await Task.sleep(for: .milliseconds(750))
                host.layoutSubtreeIfNeeded()
                try await write(host, name: "\(name)-\(label(scheme))")
            }
        }
    }

    private func fixtures() -> [HistoryMessage] {
        let now = Date.now
        return [
            HistoryMessage(id: "deploy", body: "Deploy migration 0052 and the Worker to production?",
                agentName: "claude", direction: "agent_to_boss", status: "delivered", priority: "high",
                metadata: MessageMetadata(options: ["Deploy", "Not yet"], defaultOption: "Not yet",
                    content: "Adds a table and a column. The rollback has been verified."),
                expiresAt: AttentionTestSupport.iso(now.addingTimeInterval(1080)),
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-30)),
                sessionId: "hiboss", sessionLabel: "hiboss", sessionBranch: "main",
                sessionStatus: "waiting"),
            HistoryMessage(id: "review", body: "Which navigation should we ship?", agentName: "design",
                direction: "agent_to_boss", status: "delivered", priority: "normal",
                metadata: MessageMetadata(options: ["Sidebar", "Tabs"]),
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-90)),
                sessionId: "design", sessionLabel: "mac-client", sessionBranch: "ui-v4",
                sessionStatus: "waiting"),
            HistoryMessage(id: "working", body: "Running the release verification suite.", agentName: "build",
                direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-20)),
                sessionId: "build", sessionLabel: "hiboss", sessionBranch: "release",
                sessionStatus: "working"),
            HistoryMessage(id: "result", body: "Rollback verified on staging. All checks passed.",
                agentName: "claude", direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: AttentionTestSupport.iso(now.addingTimeInterval(-120)),
                sessionId: "hiboss", sessionLabel: "hiboss", sessionBranch: "main", sessionStatus: "waiting")
        ]
    }

    private func makeWindow(_ host: NSView, size: NSSize, scheme: ColorScheme) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        NSApp.activate(ignoringOtherApps: true)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func label(_ scheme: ColorScheme) -> String { scheme == .light ? "light" : "dark" }

    private func write(_ host: NSView, name: String, minimumWidth: Int = 400) async throws {
        host.window?.displayIfNeeded()
        if !name.hasPrefix("island-"),
           let directory = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"] {
            // Let the native compositor finish while the main run loop remains responsive.
            try await Task.sleep(for: .milliseconds(750))
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let window = try XCTUnwrap(host.window)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                url.appendingPathComponent("\(name).png").path]
            try capture.run()
            try await waitForCondition { !capture.isRunning }
            XCTAssertEqual(capture.terminationStatus, 0)
        }
        // Caching display can disturb composited layers; capture the window before it.
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        let appearance = try XCTUnwrap(host.effectiveAppearance)
        appearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        XCTAssertGreaterThan(bitmap.pixelsWide, minimumWidth)
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name)-bitmap.png"))
        // Native bitmap capture reliably includes the notch overlay's composited controls.
        if name.hasPrefix("island-") {
            try png.write(to: url.appendingPathComponent("\(name).png"))
        }
    }
}
