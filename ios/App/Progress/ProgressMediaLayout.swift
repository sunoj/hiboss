// Aspect clamps and mosaic metrics for the progress media group.
// Exports: ProgressMediaLayout.
// Dependencies: CoreGraphics.

import CoreGraphics
import Foundation

enum ProgressMediaLayout {
    static let groupAspect: CGFloat = 16 / 9
    static let maxLandscapeAspect: CGFloat = 2
    static let minPortraitAspect: CGFloat = 3 / 4
    static let gap: CGFloat = 2
    static let cornerRadius: CGFloat = 16

    static func clampedAspect(width: Int?, height: Int?, measured: CGFloat? = nil) -> CGFloat {
        let raw: CGFloat?
        if let width, let height, width > 0, height > 0 {
            raw = CGFloat(width) / CGFloat(height)
        } else {
            raw = measured
        }
        guard let raw, raw > 0 else { return groupAspect }
        return min(max(raw, minPortraitAspect), maxLandscapeAspect)
    }

    static func durationLabel(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
