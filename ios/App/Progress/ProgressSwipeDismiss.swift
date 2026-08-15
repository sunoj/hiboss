// Decision helpers for zoom-1 swipe-down dismiss in the progress media viewer.
// Exports: ProgressSwipeDismiss.
// Dependencies: CoreGraphics.

import CoreGraphics

enum ProgressSwipeDismiss {
    static let threshold: CGFloat = 120
    static let zoomedScale: CGFloat = 1.01

    static func shouldBegin(zoomScale: CGFloat, velocity: CGPoint) -> Bool {
        guard zoomScale <= zoomedScale else { return false }
        if abs(velocity.x) > abs(velocity.y) { return false }
        return velocity.y >= 0
    }

    static func dragOffset(translation: CGPoint, zoomScale: CGFloat) -> CGFloat {
        guard zoomScale <= zoomedScale else { return 0 }
        return max(0, translation.y)
    }

    static func shouldDismiss(offset: CGFloat, zoomScale: CGFloat) -> Bool {
        zoomScale <= zoomedScale && offset > threshold
    }
}
