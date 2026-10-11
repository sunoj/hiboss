// Rendered registered avatars, loading/error initials, and circular image clipping.
// Dependencies: SwiftUI ImageRenderer, UIKit, XCTest, and native AgentAvatarView.

import HibossKit
import SwiftUI
import XCTest
@testable import HiBoss

@MainActor
final class AgentAvatarTests: XCTestCase {
    func testRegisteredDemoLookupReplacesInitialsInAvatarView() throws {
        let previous = ProcessInfo.processInfo.environment["HIBOSS_DEMO"]
        setenv("HIBOSS_DEMO", "1", 1)
        defer {
            if let previous { setenv("HIBOSS_DEMO", previous, 1) }
            else { unsetenv("HIBOSS_DEMO") }
        }
        let avatars = AgentAvatarStore(agents: [AgentAvatarDemo.agent(name: "worker-design")])
        let view = AgentAvatarView(name: "worker-design", size: 40).environment(\.agentAvatars, avatars)
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        XCTAssertEqual(try rendered(view),
            try rendered(AgentAvatarContent(name: "worker-design", size: 40, phase: .success(image))))
        XCTAssertNotEqual(try rendered(view),
            try rendered(AgentAvatarContent(name: "worker-design", size: 40, phase: .empty)))
    }

    func testAvatarLayoutRemainsSquareForEveryPhaseAndProposal() throws {
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        let phases: [AsyncImagePhase] = [.empty, .failure(URLError(.cannotConnectToHost)), .success(image)]
        for size: CGFloat in [20, 22, 40, 80] {
            for proposal in [CGSize(width: 8, height: 8), CGSize(width: 400, height: 800)] {
                for phase in phases {
                    let host = UIHostingController(rootView: AgentAvatarContent(
                        name: "Long Agent Name", size: size, phase: phase)
                        .environment(\.dynamicTypeSize, .accessibility5))
                    XCTAssertEqual(host.sizeThatFits(in: proposal), CGSize(width: size, height: size))
                }
                let avatars = AgentAvatarStore(agents: [BossAgent(id: "pending", name: "Long Agent Name",
                    avatarURL: URL(string: "https://demo.hiboss.invalid/pending.png"))])
                for lookup in [AgentAvatarStore(), avatars] {
                    let view = AgentAvatarView(name: "Long Agent Name", size: size)
                    let host = UIHostingController(rootView: view
                        .environment(\.agentAvatars, lookup).environment(\.dynamicTypeSize, .accessibility5))
                    XCTAssertEqual(host.sizeThatFits(in: proposal), CGSize(width: size, height: size))
                }
            }
        }
    }

    func testBundledDemoAvatarRendersAnImage() throws {
        let image = try XCTUnwrap(AgentAvatarDemo.image)
        let success = AgentAvatarContent(name: "worker-design", size: 40, phase: .success(image))
        let initials = AgentAvatarContent(name: "worker-design", size: 40, phase: .empty)
        XCTAssertNotEqual(try rendered(success), try rendered(initials))
    }

    func testLoadingFailureAndMissingAvatarKeepExistingInitials() throws {
        let empty = AgentAvatarContent(name: "Build Agent", size: 40, phase: .empty)
        let failure = AgentAvatarContent(name: "Build Agent", size: 40,
            phase: .failure(URLError(.cannotConnectToHost)))
        XCTAssertEqual(try rendered(empty), try rendered(failure))
        XCTAssertEqual(try rendered(AgentAvatarView(name: "Build Agent", size: 40)), try rendered(empty))
        XCTAssertNotEqual(try rendered(empty),
            try rendered(AgentAvatarContent(name: "Other Worker", size: 40, phase: .empty)))
    }

    func testSuccessfulImageReplacesInitialsAndStaysCircular() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        for size: CGFloat in [20, 40, 80] {
            let success = AgentAvatarContent(name: "Build Agent", size: size,
                phase: .success(Image(uiImage: image)))
            XCTAssertNotEqual(try rendered(success),
                try rendered(AgentAvatarContent(name: "Build Agent", size: size, phase: .empty)))
            let actual = try alphaMask(success)
            let expected = try alphaMask(Circle().fill(.black).frame(width: size, height: size))
            XCTAssertEqual(actual.count, expected.count)
            XCTAssertEqual(zip(actual, expected).filter { abs(Int($0) - Int($1)) > 2 }.count, 0)
        }
    }

    private func rendered<Content: View>(_ content: Content) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }

    private func alphaMask<Content: View>(_ content: Content) throws -> [UInt8] {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width,
                height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
