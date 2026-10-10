// Checks Session headings structurally against the toolbar and measures their on-screen contrast.
// Exports: SessionToolbarLayoutTests; HIBOSS_V4_SNAPSHOTS saves compositor PNG evidence.
// Dependencies: AppKit, SwiftUI, ImageIO, and production MainView with session fixtures.

import AppKit
import HibossKit
import ImageIO
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class SessionToolbarLayoutTests: XCTestCase {
    private static let sizes: [(name: String, size: NSSize)] = [("", NSSize(width: 1320, height: 820)),
        ("tall-", NSSize(width: 1320, height: 1060)), ("minimum-", NSSize(width: 480, height: 820))]

    func testSessionHeadingsLieBelowToolbarAndStayLegibleInEveryAppearanceAndSize() async throws {
        _ = NSApplication.shared
        let media = HistorySnapshotMediaServer()
        defer { media.stop() }
        try await media.start()
        for scheme in [ColorScheme.light, .dark] {
            for (layout, size) in Self.sizes {
                let name = "session-\(layout)\(scheme == .light ? "light" : "dark")"
                let probe = LayoutProbe()
                let host = NSHostingView(rootView: MainView(settings: AppSettings(), flow: OptionFlowStore(),
                    initialDestination: .session("hiboss"),
                    previewHistory: PhaseBSnapshotFixtures.history(baseURL: media.baseURL),
                    previewSessions: PhaseBSnapshotFixtures.inventory,
                    boxProvider: { ScriptedBoxBrowser(media: BoxBrowserFixtures.imageData()) },
                    panelsModel: PanelsModel(demoMode: true, autoload: false))
                    .environment(\.colorScheme, scheme).environment(\.layoutProbe, probe))
                host.sizingOptions = []
                let window = try await show(host, size: size, scheme: scheme)
                defer { window.close() }
                try await waitForCondition { probe.anchors["session.title"]?.window != nil }
                let image = try await capture(window, name: name)
                try assertHeading("session.title", probe: probe, in: window, image: image, name: name)
                if size.width >= 1000 {
                    try assertHeading("session.inspector.title", probe: probe, in: window, image: image, name: name)
                } else {
                    try await checkCompactInspector(window, probe: probe, name: name)
                }
            }
        }
    }

    /// At minimum width the inspector button sits in the toolbar overflow menu; this sends the
    /// action its overflow menu item sends.
    private func checkCompactInspector(_ window: NSWindow, probe: LayoutProbe, name: String) async throws {
        let items = window.toolbar?.items ?? []
        let item = try XCTUnwrap(items.first { $0.label == "Session details" },
            "\(name): toolbar items \(items.map(\.label))")
        let menuItem = try XCTUnwrap(item.menuFormRepresentation, "\(name): Session details has no overflow menu item")
        let action = try XCTUnwrap(menuItem.action, "\(name): Session details has no action")
        XCTAssertTrue(NSApp.sendAction(action, to: menuItem.target, from: menuItem))
        try await waitForCondition { window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        defer { window.endSheet(sheet) }
        try await waitForCondition { probe.anchors["session.inspector.title"]?.window === sheet }
        let image = try await capture(window, name: "\(name)-inspector")
        try assertHeading("session.inspector.title", probe: probe, in: sheet, image: image,
            imageFrame: window.frame, name: name)
    }

    /// The anchor is an AppKit view behind the heading; the content layout rect excludes the toolbar.
    private func assertHeading(_ id: String, probe: LayoutProbe, in window: NSWindow, image: CGImage,
                               imageFrame: NSRect? = nil, name: String, line: UInt = #line) throws {
        let anchor = try XCTUnwrap(probe.anchors[id], "\(name): \(id) is missing", line: line)
        XCTAssertTrue(anchor.window === window, "\(name): \(id) is in another window", line: line)
        let frame = anchor.convert(anchor.bounds, to: nil)
        let content = window.contentLayoutRect
        XCTAssertFalse(frame.isEmpty, "\(name): \(id) has no frame", line: line)
        XCTAssertLessThanOrEqual(frame.maxY, content.maxY,
            "\(name): \(id) top \(frame.maxY) is above the content layout top \(content.maxY)", line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, content.minY,
            "\(name): \(id) is below the window content", line: line)
        let ratio = contrast(of: window.convertToScreen(frame), in: image, imageFrame: imageFrame ?? window.frame)
        XCTAssertGreaterThanOrEqual(ratio, 4.5,
            "\(name): \(id) contrast \(ratio) means something covers the heading", line: line)
    }

    /// WCAG contrast between the darkest and lightest pixels inside a screen frame. A sheet is
    /// captured composited in its parent, so `imageFrame` is the screen frame the image covers.
    private func contrast(of frame: CGRect, in image: CGImage, imageFrame: NSRect) -> Double {
        let scale = CGFloat(image.width) / imageFrame.width
        let rect = CGRect(x: (frame.minX - imageFrame.minX) * scale, y: (imageFrame.maxY - frame.maxY) * scale,
            width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = image.cropping(to: rect) else { return 0 }
        let width = crop.width, height = crop.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var low = 1.0, high = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = luminance(pixels[index], pixels[index + 1], pixels[index + 2])
            low = min(low, value)
            high = max(high, value)
        }
        return (high + 0.05) / (low + 0.05)
    }

    private func luminance(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func capture(_ window: NSWindow, name: String) async throws -> CGImage {
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
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Opens the window with room for SwiftUI to add its toolbar, as a scene window has, then
    /// resizes it. A window that is already screen-height when SwiftUI adds the toolbar cannot
    /// grow, and the detail column then draws a stale toolbar band over its headings.
    private func show(_ host: NSView, size: NSSize, scheme: ColorScheme) async throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: size.width, height: 600),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        host.appearance = window.appearance
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try await waitForCondition { window.toolbar != nil }
        try await Task.sleep(for: .milliseconds(250))
        let visible = try XCTUnwrap(window.screen?.visibleFrame)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: visible.minX + 80, y: visible.maxY - frame.height)
        window.setFrame(frame, display: true)
        print("Session snapshot window \(size) -> content \(window.contentLayoutRect.size)")
        return window
    }
}
