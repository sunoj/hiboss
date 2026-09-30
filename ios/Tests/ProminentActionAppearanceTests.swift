// Renders native decision buttons in both appearances and submission states.
// Exports: ProminentActionAppearanceTests; keeps screenshots for contrast review.
// Dependencies: XCTest, SwiftUI, UIKit, HiBoss, HibossKit.

import HibossKit
import SwiftUI
import XCTest
@testable import HiBoss

@MainActor
final class ProminentActionAppearanceTests: XCTestCase {
    func testLightDecisionLabelsRemainVisibleWhileSubmitting() async throws {
        try await verifyAppearance(.light)
    }

    func testDarkDecisionLabelsRemainVisibleWhileSubmitting() async throws {
        try await verifyAppearance(.dark)
    }

    private func verifyAppearance(_ appearance: UIUserInterfaceStyle) async throws {
        let now = Date()
        let message = HistoryMessage(
            id: "contrast", body: "Continue?", direction: "agent_to_boss",
            status: "delivered", priority: "normal",
            metadata: MessageMetadata(options: ["Continue", "Later"], defaultOption: "Continue"),
            expiresAt: now.addingTimeInterval(600).ISO8601Format(), createdAt: now.ISO8601Format()
        )
        for submitting: String? in [nil, "Later", "Continue"] {
            let view = DecisionOptions(
                options: ["Continue", "Later"], timing: DecisionTiming(message: message, now: now),
                submitting: submitting, onChoose: { _ in }
            )
            .tint(Theme.accent)
            .background(Theme.paper)
            .ignoresSafeArea()
            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = appearance
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 100))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let state = submitting == nil ? "enabled" : submitting == "Continue" ? "in-flight" : "disabled"
            let name = "prominent-\(appearance == .dark ? "dark" : "light")-\(state)"
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(try labelContrast(image), 3, name)
        }
    }

    private func labelContrast(_ image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var luminances: [Double] = []
        // The 360x100 window renders the two buttons in its top ~57%; the left label sits at
        // roughly 20–38% of the height, so sample there rather than the window's middle.
        for y in Int(Double(height) * 0.2)..<Int(Double(height) * 0.38) {
            for x in Int(Double(width) * 0.12)..<Int(Double(width) * 0.35) {
                let offset = (y * width + x) * 4
                let channels = (0..<3).map { channel -> Double in
                    let value = Double(pixels[offset + channel]) / 255
                    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                }
                luminances.append(channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722)
            }
        }
        luminances.sort()
        let low = luminances[luminances.count / 20]
        let high = luminances[luminances.count * 19 / 20]
        return (high + 0.05) / (low + 0.05)
    }
}
