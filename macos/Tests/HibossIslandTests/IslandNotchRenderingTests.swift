// Renders actual Island content in offscreen native windows with synthetic camera housings.
// Exports: IslandNotchRenderingTests; optional PNG output via HIBOSS_NOTCH_SNAPSHOTS.
// Dependencies: AppKit bitmap capture, SwiftUI, XCTest and IslandNotchFixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class IslandNotchRenderingTests: XCTestCase {
    func testCollapsedContentIsFullyBelowBothSimulatedNotches() async throws {
        for (name, geometry) in fixtures {
            let bitmap = try await render(flow: OptionFlowStore(), geometry: geometry, expanded: false)
            let scale = CGFloat(bitmap.pixelsWide) / geometry.collapsedFrame.width
            let housing = housingRect(geometry, panel: geometry.collapsedFrame)
            assertBlack(bitmap, in: housing, scale: scale)
            XCTAssertEqual(neutralPixels(bitmap, top: 0, bottom: 32, scale: scale), 0)
            XCTAssertGreaterThan(neutralPixels(bitmap, top: 32, bottom: 68, scale: scale), 20)
            try write(bitmap, name: "\(name)-collapsed")
        }
    }

    func testExpandedHeaderAndExpiryBandStayOutsideBothSimulatedNotches() async throws {
        let message = OptionMessage.fixture(id: "notch-render", options: ["Ship", "Wait"],
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)))
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        defer { flow.disconnect() }
        flow.connect(api: ScriptedBossAPI(messages: [message]))
        try await waitForCondition { flow.activeMessage?.id == message.id }
        for (name, geometry) in fixtures {
            let frame = geometry.expandedFrame(contentHeight: OptionPanelLayout.expandedHeight(for: message))
            let bitmap = try await render(flow: flow, geometry: geometry, expanded: true)
            let scale = CGFloat(bitmap.pixelsWide) / frame.width
            assertBlack(bitmap, in: housingRect(geometry, panel: frame), scale: scale)
            XCTAssertEqual(neutralPixels(bitmap, top: 0, bottom: 32, scale: scale), 0)
            XCTAssertGreaterThan(neutralPixels(bitmap, top: 45, bottom: 80, scale: scale), 20)
            let side = CGRect(x: 0, y: 0, width: 4, height: 32)
            XCTAssertGreaterThan(greenPixels(bitmap, in: side, scale: scale), 0)
            XCTAssertGreaterThan(greenPixels(bitmap,
                in: CGRect(x: 0, y: frame.height - 4, width: frame.width, height: 4), scale: scale), 0)
            try write(bitmap, name: "\(name)-expanded")
        }
    }

    func testResolvedQuestionAlsoClearsNotch() async throws {
        let message = OptionMessage.fixture(id: "notch-resolved", options: ["Ship", "Wait"])
        let flow = OptionFlowStore(reconnectDelay: .seconds(60))
        defer { flow.disconnect() }
        let resolution = OptionResolution(id: message.id, status: .replied, answer: "Ship", source: "Phone")
        flow.connect(api: ScriptedBossAPI(events: [.message(message), .resolved(resolution)],
            eventInterval: .milliseconds(100)))
        try await waitForCondition {
            if case .resolved = flow.presentationState { return true }
            return false
        }
        let geometry = IslandNotchFixtures.macBook14
        let bitmap = try await render(flow: flow, geometry: geometry, expanded: true)
        let frame = geometry.expandedFrame(contentHeight: OptionPanelLayout.expandedHeight(for: message))
        let scale = CGFloat(bitmap.pixelsWide) / frame.width
        assertBlack(bitmap, in: housingRect(geometry, panel: frame), scale: scale)
        XCTAssertEqual(neutralPixels(bitmap, top: 0, bottom: 32, scale: scale), 0)
        XCTAssertGreaterThan(neutralPixels(bitmap, top: 46, bottom: 80, scale: scale), 20)
        try write(bitmap, name: "macbook14-resolved")
    }

    private var fixtures: [(String, IslandGeometry)] {
        [("macbook14", IslandNotchFixtures.macBook14), ("macbook16", IslandNotchFixtures.macBook16)]
    }

    private func render(
        flow: OptionFlowStore, geometry: IslandGeometry, expanded: Bool
    ) async throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let frame = expanded ? geometry.expandedFrame(
            contentHeight: OptionPanelLayout.expandedHeight(for: try XCTUnwrap(flow.activeMessage))
        ) : geometry.collapsedFrame
        let host = NSHostingView(rootView: IslandView(flow: flow, reply: AttentionReplyState(),
            topInset: geometry.expandedTopInset).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: frame.size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func housingRect(_ geometry: IslandGeometry, panel: CGRect) -> CGRect {
        guard let notch = geometry.notchFrame else { return .zero }
        return CGRect(x: notch.minX - panel.minX, y: 0, width: notch.width, height: notch.height)
    }

    private func assertBlack(_ bitmap: NSBitmapImageRep, in rect: CGRect, scale: CGFloat) {
        XCTAssertEqual(pixels(bitmap, in: rect, scale: scale) { color in
            color.alphaComponent < 0.95
                || max(color.redComponent, color.greenComponent, color.blueComponent) > 0.04
        }, 0, "The entire camera housing must cover only the opaque black surface")
    }

    private func neutralPixels(
        _ bitmap: NSBitmapImageRep, top: CGFloat, bottom: CGFloat, scale: CGFloat
    ) -> Int {
        pixels(bitmap, in: CGRect(x: 4, y: top, width: CGFloat(bitmap.pixelsWide) / scale - 8,
            height: bottom - top), scale: scale) { color in
            color.alphaComponent > 0.8
                && min(color.redComponent, color.greenComponent, color.blueComponent) > 0.25
        }
    }

    private func greenPixels(_ bitmap: NSBitmapImageRep, in rect: CGRect, scale: CGFloat) -> Int {
        pixels(bitmap, in: rect, scale: scale) { color in
            color.greenComponent > 0.2 && color.greenComponent > color.redComponent * 1.5
                && color.greenComponent > color.blueComponent * 1.2
        }
    }

    private func pixels(
        _ bitmap: NSBitmapImageRep, in rect: CGRect, scale: CGFloat, matching predicate: (NSColor) -> Bool
    ) -> Int {
        var count = 0
        for y in Int(rect.minY * scale)..<min(bitmap.pixelsHigh, Int(rect.maxY * scale)) {
            for x in Int(rect.minX * scale)..<min(bitmap.pixelsWide, Int(rect.maxX * scale)) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), predicate(color) {
                    count += 1
                }
            }
        }
        return count
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_NOTCH_SNAPSHOTS"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
