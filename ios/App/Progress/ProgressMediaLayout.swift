// Aspect clamps and mosaic metrics for the progress media group.
// Exports: ProgressMediaLayout, ProgressMediaFrame.
// Dependencies: SwiftUI, CoreGraphics, Foundation and the shared layout scale.

import CoreGraphics
import Foundation
import SwiftUI

enum ProgressMediaLayout {
    static let groupAspect: CGFloat = 16 / 9
    static let maxLandscapeAspect: CGFloat = 2
    static let minPortraitAspect: CGFloat = 3 / 4
    static let gap: CGFloat = Space.xxs
    static let cornerRadius: CGFloat = Radius.medium

    static let wideThreshold: CGFloat = 500
    static let maximumWidth: CGFloat = 480
    static let maximumHeight: CGFloat = 320

    static func size(availableWidth: CGFloat, aspect: CGFloat) -> CGSize {
        let width = availableWidth > wideThreshold
            ? min(availableWidth, maximumWidth, maximumHeight * aspect) : availableWidth
        return CGSize(width: width, height: width / aspect)
    }

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

struct ProgressMediaFrame: Layout {
    let aspect: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        ProgressMediaLayout.size(availableWidth: proposal.width ?? ProgressMediaLayout.maximumWidth,
                                 aspect: aspect)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
