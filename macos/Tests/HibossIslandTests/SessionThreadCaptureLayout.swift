// Capture sizing for the complete session fixture, independent of display height.
// Exports: SessionThreadCaptureLayout; production window sizing is unaffected.
// Dependencies: Foundation geometry values.

import Foundation

enum SessionThreadCaptureLayout {
    static func contentSize(in screen: CGSize) -> CGSize {
        CGSize(width: min(1280, screen.width - 40), height: 1600)
    }
}
