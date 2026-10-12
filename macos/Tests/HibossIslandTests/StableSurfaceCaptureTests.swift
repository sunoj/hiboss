// Captures real main windows before and after the stability changes in both appearances.
// Exports StableSurfaceCaptureTests; HIBOSS_STABILITY_SCREENSHOTS selects the evidence directory.
// Dependencies: AppKit compositor capture, MainView, and deterministic local service fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class StableSurfaceCaptureTests: XCTestCase {
    func testMainWindowEvidence() async throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_STABILITY_SCREENSHOTS"] else {
            return
        }
        for scheme in [ColorScheme.light, .dark] {
            for (name, destination, clear) in [
                ("today-all-clear", OverviewDestination.today, true),
                ("today-decision", .today, false),
                ("session", .session("session"), false),
                ("progress", .progress, false),
                ("history", .category(.all), false),
                ("device-requests", .deviceRequests, true),
                ("panels", .today, true)
            ] {
                let api = ScriptedProgressAPI()
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                    initialDestination: destination,
                    previewHistory: name == "panels" ? nil : clear ? [] : [Self.question],
                    progressProvider: { api }, panelsModel: PanelsModel(demoMode: true, autoload: false))
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = try await StableWindowSupport.show(host, scheme: scheme)
                defer { window.close() }
                try await StableWindowSupport.capture(window, directory: directory,
                    name: "\(name)-\(scheme == .light ? "light" : "dark")")
            }
        }
    }

    static var question: HistoryMessage {
        HistoryMessage(id: "decision", body: "Ship the native workspace improvements?",
            agentName: "Builder",
            direction: "agent_to_boss", status: "delivered", priority: "high",
            metadata: MessageMetadata(options: ["Ship", "Review first"]),
            createdAt: AttentionTestSupport.iso(.now.addingTimeInterval(-120)),
            sessionId: "session", sessionLabel: "HiBoss", sessionBranch: "workspace", sessionStatus: "waiting")
    }
}

@MainActor
enum StableWindowSupport {
    static func show(_ host: NSView, scheme: ColorScheme = .light) async throws -> NSWindow {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1160, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(400))
        let visible = try XCTUnwrap(window.screen?.visibleFrame)
        var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 1160, height: 760))
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: visible.minX + 40, y: visible.maxY - frame.height)
        window.setFrame(frame, display: true)
        return window
    }

    static func capture(_ window: NSWindow, directory: String, name: String) async throws {
        try await Task.sleep(for: .milliseconds(750))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
        let image = try XCTUnwrap(NSImage(contentsOfFile: path))
        XCTAssertGreaterThanOrEqual(image.size.width, window.frame.width)
    }

    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
