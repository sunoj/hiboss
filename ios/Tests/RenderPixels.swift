// RGBA extraction and full-image alpha masks for rendered iOS test surfaces.
// Exports rgbaPixels and alphaMask; depends on XCTest, Core Graphics and SwiftUI ImageRenderer.

import SwiftUI
import XCTest

func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
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

@MainActor
func alphaMask<Content: View>(_ content: Content) throws -> [UInt8] {
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    let image = try XCTUnwrap(renderer.uiImage?.cgImage)
    let pixels = try rgbaPixels(image)
    return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
}
