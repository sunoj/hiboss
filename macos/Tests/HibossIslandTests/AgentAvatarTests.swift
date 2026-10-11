// Rendered registered avatars, loading/error initials, and circular image clipping.
// Dependencies: SwiftUI ImageRenderer, AppKit, XCTest, and native AgentAvatarView.

import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class AgentAvatarTests: XCTestCase {
    func testUnidentifiedMessageRowKeepsInitialsWhenFallbackNameHasAvatar() throws {
        let key = "HIBOSS_ATTENTION_PREVIEW"
        let previous = ProcessInfo.processInfo.environment[key]
        setenv(key, "1", 1)
        defer {
            if let previous { setenv(key, previous, 1) }
            else { unsetenv(key) }
        }
        for agentName: String? in [nil, "", " \n"] {
            let message = HistoryMessage(id: "unidentified", body: "Build finished", agentName: agentName,
                direction: "agent_to_boss", status: "delivered", priority: "normal",
                createdAt: "2026-10-11T12:00:00Z")
            let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "Agent"),
                AgentAvatarDemo.agent(name: message.historyDisplayName),
                AgentAvatarDemo.agent(name: agentName ?? "Agent")])
            let row = HistoryThreadRow(thread: MessageThread(message: message),
                reply: AttentionReplyState(), isExpanded: .constant(false), isSearching: false,
                onCollapse: {}, onChoose: { _ in nil }).frame(width: 500)
            try assertSamePixels(row.environment(\.agentAvatars, avatars), row)
        }
    }

    func testMissingAndBlankLookupNamesPreserveDisplayInitials() throws {
        let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "Agent")])
        let initials = AgentAvatarContent(name: "Agent", size: 40, phase: .empty)
        for lookupName: String? in [nil, "", " \n"] {
            let view = AgentAvatarView(name: "Agent", size: 40, lookupName: lookupName)
                .environment(\.agentAvatars, avatars)
            try assertSamePixels(view, initials)
        }
        for name in ["", " \n"] {
            let store = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: name)])
            let view = AgentAvatarView(name: name, size: 40).environment(\.agentAvatars, store)
            try assertSamePixels(view, AgentAvatarContent(name: name, size: 40, phase: .empty))
        }
    }

    func testBundledDemoAvatarRendersAnImage() throws {
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        let success = AgentAvatarContent(name: "Preview Agent", size: 40, phase: .success(image))
        let initials = AgentAvatarContent(name: "Preview Agent", size: 40, phase: .empty)
        XCTAssertTrue(try rendered(success) != rendered(initials))
    }

    func testLoadingFailureAndMissingAvatarKeepExistingInitials() throws {
        let empty = AgentAvatarContent(name: "Build Agent", size: 40, phase: .empty)
        let failure = AgentAvatarContent(name: "Build Agent", size: 40,
            phase: .failure(URLError(.cannotConnectToHost)))
        try assertSamePixels(empty, failure)
        try assertSamePixels(AgentAvatarView(name: "Build Agent", size: 40), empty)
        XCTAssertNotEqual(try rendered(empty),
            try rendered(AgentAvatarContent(name: "Other Worker", size: 40, phase: .empty)))
    }

    func testSuccessfulImageReplacesInitialsAndStaysCircular() throws {
        let image = NSImage(size: NSSize(width: 80, height: 40), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        for size: CGFloat in [20, 40, 80] {
            let success = AgentAvatarContent(name: "Build Agent", size: size,
                phase: .success(Image(nsImage: image)))
            let initialPixels = try rendered(
                AgentAvatarContent(name: "Build Agent", size: size, phase: .empty))
            XCTAssertTrue(try rendered(success) != initialPixels, "The registered image replaces initials")
            let actual = try alphaMask(success)
            let expected = try alphaMask(Circle().fill(.black).frame(width: size, height: size))
            XCTAssertEqual(actual.count, expected.count)
            XCTAssertEqual(zip(actual, expected).filter { abs($0 - $1) > 2 / 255 + 0.0001 }.count, 0)
        }
    }

    private func rendered<Content: View>(_ content: Content) throws -> [UInt8] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width,
                height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func assertSamePixels<A: View, B: View>(_ first: A, _ second: B) throws {
        let actual = try rendered(first)
        let expected = try rendered(second)
        XCTAssertEqual(actual.count, expected.count)
        XCTAssertEqual(zip(actual, expected).filter { abs(Int($0) - Int($1)) > 2 }.count, 0)
    }

    private func alphaMask<Content: View>(_ content: Content) throws -> [CGFloat] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(renderer.nsImage?.tiffRepresentation)))
        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        }
    }
}
