// Full-window session thread captures with a decision, reply, follow-up and merged updates.
// Exports: SessionThreadWindowTests; screenshots live outside the source checkout.
// Dependencies: AppKit, SwiftUI, XCTest, production MainView and window capture support.

import AppKit
import HibossKit
import SwiftUI
import XCTest
import Vision
@testable import HibossIsland

@MainActor
final class SessionThreadWindowTests: XCTestCase {
    func testSessionThreadsInLightAndDark() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        let history = SessionThreadFixtures.history()
        let folded = MessageThread.fold(history)
        XCTAssertEqual(folded.first { $0.id == "answered" }?.entries.count, 2)
        XCTAssertEqual(SessionThreadLogic.reactionChips(history[3]).first?.text, "👍 2")
        // SessionThreadEntries renders all members; the real workspace supplies chrome and Watching.
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                initialDestination: .session("thread-demo"), previewHistory: history,
                panelsModel: PanelsModel(demoMode: false, autoload: false))
                .environment(\.colorScheme, scheme))
            host.sizingOptions = []
            let window = show(host, scheme: scheme)
            defer { window.close() }
            try await waitForCondition { window.toolbar != nil }
            fitWindow(window)
            try await BoxWindowCaptureSupport.settle(window)
            let directory = "/private/tmp/hiboss-thread-ui-followup"
            let name = "session-threads-\(scheme == .light ? "light" : "dark")"
            let text = try await capture(window, directory: directory, name: name)
            let expectedText = [
                "Needs you", "You chose Review", "Review complete", "Indexed the changed files",
                "Validated the message models", "Prepared the review summary"
            ]
            for expected in expectedText {
                XCTAssertTrue(text.localizedCaseInsensitiveContains(expected),
                    "Missing \(expected): \(text)")
            }
            XCTAssertGreaterThan(host.bounds.width, 600)
        }
    }

    private func capture(_ window: NSWindow, directory: String, name: String) async throws -> String {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try process.run()
        try await waitForCondition { !process.isRunning }
        XCTAssertEqual(process.terminationStatus, 0)
        let image = try XCTUnwrap(NSImage(contentsOfFile: path))
        var rect = NSRect(origin: .zero, size: image.size)
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: pixels).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }

    private func show(_ host: NSView, scheme: ColorScheme) -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1280, screen.width - 40), height: 500)
        let window = SessionThreadCaptureWindow(contentRect: NSRect(origin: screen.origin, size: size),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func fitWindow(_ window: NSWindow) {
        guard let screen = window.screen?.visibleFrame else { return }
        let size = SessionThreadCaptureLayout.contentSize(in: screen.size)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: screen.midX - frame.width / 2, y: screen.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
}

// A full-content capture can extend below the display without clipping the session surface.
// This affects only test windows; the application keeps the native sizing constraints.
private final class SessionThreadCaptureWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
