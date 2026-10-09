// Checks session headings against the native toolbar in full and minimum-width windows.
// Exports: SessionToolbarLayoutTests; HIBOSS_V4_SNAPSHOTS saves compositor PNG evidence.
// Dependencies: AppKit, SwiftUI, Vision, and production MainView with session fixtures.

import AppKit
import HibossKit
import SwiftUI
import Vision
import XCTest
@testable import HibossIsland

@MainActor
final class SessionToolbarLayoutTests: XCTestCase {
    func testSessionHeadingsStayBelowToolbarInBothAppearancesAndWindowWidths() async throws {
        _ = NSApplication.shared
        let media = HistorySnapshotMediaServer()
        defer { media.stop() }
        try await media.start()
        for scheme in [ColorScheme.light, .dark] {
            for size in [NSSize(width: 1320, height: 820), NSSize(width: 1320, height: 1060),
                         NSSize(width: 480, height: 820)] {
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                    initialDestination: .session("hiboss"),
                    previewHistory: PhaseBSnapshotFixtures.history(baseURL: media.baseURL),
                    previewSessions: PhaseBSnapshotFixtures.inventory,
                    boxProvider: { ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData()) },
                    panelsModel: PanelsModel(demoMode: true, autoload: false))
                    .environment(\.colorScheme, scheme))
                host.sizingOptions = []
                let window = show(host, size: size, scheme: scheme)
                defer { window.close() }
                try await waitForCondition {
                    self.descendants(host).contains { ($0 as? NSTextField)?.isEditable == true }
                }
                let layout = size.width == 480 ? "minimum-" : size.height == 1060 ? "tall-" : ""
                let name = "session-\(layout)\(scheme == .light ? "light" : "dark")"
                let observations = try await capture(window, name: name)
                if let branch = observations.first(where: {
                    $0.text.contains("ui-v4") && $0.bounds.midY > 0.85 && $0.bounds.midX < 0.65
                }) {
                    assertBelowToolbar(branch.bounds, window: window)
                } else {
                    XCTFail("\(name): The project/branch heading must be readable below the toolbar")
                }
                if size.width == 1320 {
                    if let inspector = observations.first(where: { $0.text == "Session details" }) {
                        assertBelowToolbar(inspector.bounds, window: window)
                    } else {
                        XCTFail("\(name): The inspector heading must be readable below the toolbar")
                    }
                } else {
                    do {
                        try await checkCompactInspector(host, window: window, name: name)
                    } catch {
                        XCTFail("\(name): Compact inspector verification failed: \(error)")
                    }
                }
            }
        }
    }

    private func checkCompactInspector(_ host: NSView, window: NSWindow, name: String) async throws {
        let views = (window.toolbar?.items ?? []).compactMap(\.view)
        let elements = accessibilityElements(window) + views.flatMap { accessibilityElements($0) }
        let labels = elements.map { $0.accessibilityLabel() ?? $0.accessibilityTitle() ?? "" }
        let button = try XCTUnwrap(elements.first {
            $0.accessibilityRole() == .button && ($0.accessibilityLabel() == "Session details"
                || $0.accessibilityTitle() == "Session details")
        }, "Toolbar labels: \(labels)")
        XCTAssertTrue(button.accessibilityPerformPress())
        try await waitForCondition { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let observations = try await capture(sheet, name: "\(name)-inspector")
        let title = try XCTUnwrap(observations.first { $0.text == "Session details" })
        assertBelowToolbar(title.bounds, window: sheet)
        XCTAssertGreaterThan(title.bounds.minY, 0)
        XCTAssertLessThan(title.bounds.maxY, 1)
        window.endSheet(sheet)
    }

    private func assertBelowToolbar(_ bounds: CGRect, window: NSWindow,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(bounds.maxY * window.frame.height, window.contentLayoutRect.maxY,
            "The entire heading must fit below the native toolbar", file: file, line: line)
    }

    private func capture(_ window: NSWindow, name: String) async throws
        -> [(text: String, bounds: CGRect)] {
        try await Task.sleep(for: .milliseconds(750))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let directory = ProcessInfo.processInfo.environment["HIBOSS_V4_SNAPSHOTS"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("hiboss-session-toolbar").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run()
        try await waitForCondition { !capture.isRunning }
        XCTAssertEqual(capture.terminationStatus, 0)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(url: url).perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) }
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func accessibilityElements(_ element: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
        (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }
            .flatMap { [$0] + accessibilityElements($0) }
    }

    private func show(_ host: NSView, size: NSSize, scheme: ColorScheme) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
