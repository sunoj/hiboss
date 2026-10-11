// Captures a demo agent's registered image in the native message list.
// Dependencies: XCTest, offline demo fixtures, and shared demo launch support.

import XCTest
import UIKit

@MainActor
final class AgentAvatarUITests: XCTestCase {
    func testDemoRegisteredAvatarInMessageList() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.configureDemoLaunch()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleInterfaceStyle", "Light"]
        app.launchConfiguredDemo()
        app.tabBars.buttons["Sessions"].tap()
        app.buttons["Messages"].tap()
        let name = app.staticTexts["worker-design"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let avatar = CGRect(x: name.frame.minX - 52, y: name.frame.minY, width: 40, height: 40)
        XCTAssertGreaterThan(try tealPixelCount(app.screenshot().image, in: avatar), 100,
                             "the registered patterned image must replace the neutral initials circle")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "registered-agent-avatar-ios"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tealPixelCount(_ image: UIImage, in rect: CGRect) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        let scale = CGFloat(source.width) / image.size.width
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
            width: rect.width * scale, height: rect.height * scale)))
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: crop.width,
                height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return stride(from: 0, to: pixels.count, by: 4).filter { offset in
            let red = Int(pixels[offset])
            return red < 100 && Int(pixels[offset + 1]) > red + 20 && Int(pixels[offset + 2]) > red + 20
        }.count
    }
}
