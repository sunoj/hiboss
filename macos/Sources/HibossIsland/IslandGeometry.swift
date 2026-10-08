// Calculates top-edge Island frames from injected display measurements.
// Exports: IslandGeometry for panel sizing, content clearance and pointer hit testing.
// Dependencies: Foundation geometry and HibossKit's unchanged plain-screen dimensions.

import Foundation
import HibossKit

struct IslandGeometry: Equatable {
    let displayID: UInt32?
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let expandedTopInset: CGFloat
    let notchFrame: CGRect?

    private static let notchSideMargin: CGFloat = 18

    init(
        screenFrame: CGRect,
        visibleFrame: CGRect? = nil,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        displayID: UInt32? = nil
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame ?? screenFrame
        expandedTopInset = max(0, safeAreaTop)
        if safeAreaTop > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
            !left.isEmpty, !right.isEmpty, screenFrame.width - left.width - right.width > 0 {
            let width = screenFrame.width - left.width - right.width
            notchFrame = CGRect(
                x: screenFrame.midX - width / 2, y: screenFrame.maxY - safeAreaTop,
                width: width, height: safeAreaTop
            )
        } else {
            notchFrame = nil
        }
    }

    var collapsedFrame: CGRect {
        topFrame(
            width: max(
                AppConstants.Island.collapsedWidth, (notchFrame?.width ?? 0) + 2 * Self.notchSideMargin
            ),
            height: AppConstants.Island.collapsedHeight + expandedTopInset
        )
    }

    var hotZone: CGRect {
        notchFrame.map { collapsedFrame.union($0) } ?? collapsedFrame
    }

    func expandedFrame(contentHeight: CGFloat) -> CGRect {
        topFrame(
            width: max(AppConstants.Island.width, collapsedFrame.width),
            height: min(contentHeight + expandedTopInset, visibleFrame.height * 0.8)
        )
    }

    private func topFrame(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: (notchFrame?.midX ?? screenFrame.midX) - width / 2,
            y: screenFrame.maxY - height, width: width, height: height
        )
    }
}
