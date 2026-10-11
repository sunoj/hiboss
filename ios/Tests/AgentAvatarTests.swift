// Rendered registered avatars, loading/error initials, and circular image clipping.
// Dependencies: SwiftUI ImageRenderer, UIKit, XCTest, and native AgentAvatarView.

import HibossKit
import SwiftUI
import XCTest
@testable import HiBoss

@MainActor
final class AgentAvatarTests: XCTestCase {
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
