// Exercises the native avatar view through the shared lookup and public image loader.
// Dependencies: AppKit hosting, SwiftUI observation, and loopback image fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class AgentAvatarLoadingTests: XCTestCase {
    func testRegisteredImageLoadsAndSignOutReturnsToInitials() async throws {
        _ = NSApplication.shared
        let media = HistorySnapshotMediaServer()
        try await media.start()
        defer { media.stop() }
        let avatars = AgentAvatarStore(agents: [BossAgent(id: "a1", name: "Build Agent",
            avatarURL: URL(string: media.baseURL + "/ship.png"))])
        let host = NSHostingView(rootView: AgentAvatarView(name: "Build Agent", size: 80)
            .environment(\.agentAvatars, avatars))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 80, height: 80),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await waitForCondition { self.hasColoredImage(host) }
        XCTAssertEqual(media.requestedPaths, ["/ship.png"])
        avatars.disconnect()
        try await waitForCondition { !self.hasColoredImage(host) }
    }

    private func hasColoredImage(_ host: NSView) -> Bool {
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        guard let color = bitmap.colorAt(x: Int(40 * scale), y: Int(15 * scale))?
            .usingColorSpace(.deviceRGB) else { return false }
        let values = [color.redComponent, color.greenComponent, color.blueComponent]
        return (values.max() ?? 0) - (values.min() ?? 0) > 0.1
    }
}
