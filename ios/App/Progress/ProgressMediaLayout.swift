// Aspect clamps and mosaic metrics for the progress media group.
// Exports: ProgressMediaLayout.
// Dependencies: CoreGraphics, Foundation and the shared layout scale.

import CoreGraphics
import Foundation

enum ProgressMediaLayout {
    static let groupAspect: CGFloat = 16 / 9
    static let maxLandscapeAspect: CGFloat = 2
    static let minPortraitAspect: CGFloat = 3 / 4
    static let gap: CGFloat = Space.xxs
    static let cornerRadius: CGFloat = Radius.medium

    static func clampedAspect(width: Int?, height: Int?) -> CGFloat {
        let raw: CGFloat?
        if let width, let height, width > 0, height > 0 {
            raw = CGFloat(width) / CGFloat(height)
        } else {
            raw = nil
        }
        guard let raw, raw > 0 else { return groupAspect }
        return min(max(raw, minPortraitAspect), maxLandscapeAspect)
    }

    /// Locale-formatted m:ss for a video's length.
    static func durationLabel(milliseconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(max(0, milliseconds / 1000)).formatted(.time(pattern: .minuteSecond).locale(locale))
    }
}
