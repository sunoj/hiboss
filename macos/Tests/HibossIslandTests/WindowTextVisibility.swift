// Measures compositor contrast at layout anchors to catch chrome painted over valid frames.
// Exports: WindowTextVisibility.assertReadable; captures use the existing full-window harness.
// Dependencies: AppKit, ImageIO, XCTest, and LayoutProbe.

import AppKit
import ImageIO
import XCTest
@testable import HibossIsland

@MainActor
enum WindowTextVisibility {
    static func assertReadable(_ ids: [String], probe: LayoutProbe, window: NSWindow,
                               directory: String, name: String) throws {
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        for id in ids {
            let anchor = try XCTUnwrap(probe.anchors[id], "\(name): missing \(id)")
            let rect = anchor.convert(anchor.bounds, to: nil)
            XCTAssertTrue(window.contentLayoutRect.contains(rect), "\(name): clipped \(id): \(rect)")
            let ratio = contrast(window.convertToScreen(rect), image: image, windowFrame: window.frame)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name): covered \(id), contrast \(ratio)")
            print("\(name): \(id) contrast \(ratio), frame \(rect)")
        }
    }

    private static func contrast(_ frame: CGRect, image: CGImage, windowFrame: NSRect) -> Double {
        let scale = CGFloat(image.width) / windowFrame.width
        let rect = CGRect(x: (frame.minX - windowFrame.minX) * scale,
            y: (windowFrame.maxY - frame.maxY) * scale,
            width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = image.cropping(to: rect) else { return 0 }
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        var low = 1.0
        var high = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = 0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1])
                + 0.0722 * linear(pixels[index + 2])
            low = min(low, value)
            high = max(high, value)
        }
        return (high + 0.05) / (low + 0.05)
    }

    private static func linear(_ channel: UInt8) -> Double {
        let value = Double(channel) / 255
        return value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
