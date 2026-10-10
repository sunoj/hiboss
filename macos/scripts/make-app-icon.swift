// Generates a complete RGBA macOS iconset from the square iOS artwork, first fitting it to
// the macOS icon grid: white rim trimmed, an 824-of-1024 rounded square, transparent margins.
// Usage: swift make-app-icon.swift <source.png> <output.iconset>. Dependencies: AppKit.

import AppKit
import Foundation

struct IconSpec {
    let pixels: Int
    let filename: String
}

let specs = [
    IconSpec(pixels: 16, filename: "icon_16x16.png"),
    IconSpec(pixels: 32, filename: "icon_16x16@2x.png"),
    IconSpec(pixels: 32, filename: "icon_32x32.png"),
    IconSpec(pixels: 64, filename: "icon_32x32@2x.png"),
    IconSpec(pixels: 128, filename: "icon_128x128.png"),
    IconSpec(pixels: 256, filename: "icon_128x128@2x.png"),
    IconSpec(pixels: 256, filename: "icon_256x256.png"),
    IconSpec(pixels: 512, filename: "icon_256x256@2x.png"),
    IconSpec(pixels: 512, filename: "icon_512x512.png"),
    IconSpec(pixels: 1024, filename: "icon_512x512@2x.png"),
]

guard CommandLine.arguments.count == 3 else {
    fatalError("Expected source image and output iconset paths")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Unable to read source image")
}

/// The iOS artwork paints its own rounded square inside a white rim; crop the inner 94% and
/// mask it so the corners are transparent instead of white on every macOS background.
func macGridImage(_ source: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        let body = NSRect(x: 100, y: 90, width: 824, height: 824)
        let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 24
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        path.addClip()
        let inset = source.size.width * 0.03
        source.draw(in: body, from: NSRect(x: inset, y: inset, width: source.size.width - 2 * inset,
            height: source.size.height - 2 * inset), operation: .copy, fraction: 1)
        return true
    }
}

let gridImage = macGridImage(sourceImage)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for spec in specs {
    let size = NSSize(width: spec.pixels, height: spec.pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: spec.pixels,
        pixelsHigh: spec.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Unable to create icon bitmap") }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    gridImage.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon bitmap")
    }
    try data.write(to: outputURL.appendingPathComponent(spec.filename))
}
