// Restores the 420pt presentation width before the live option content is laid out.
// Exports: IslandPanelController width-restore helpers.
// Dependencies: AppKit, IslandGeometry, AppConstants.

import AppKit
import HibossKit

extension IslandPanelController {
    /// The live height report is accepted only at the presentation width, so restore it first:
    /// a drop-target reveal or a boss-widened window leaves a different width behind.
    func restoreIslandWidth(_ geometry: IslandGeometry) {
        setContentInset(geometry.expandedTopInset)
        let expanded = geometry.expandedFrame(contentHeight: panel.frame.height)
        let frame = NSRect(x: expanded.minX, y: panel.frame.minY,
                           width: expanded.width, height: panel.frame.height)
        guard panel.frame != frame else { return }
        panel.orderOut(nil)
        panel.setFrame(frame, display: false)
    }

    func restoreWindowWidth() {
        guard let size = optionWindow.contentView?.frame.size, size.width != AppConstants.Island.width
        else { return }
        optionWindow.orderOut(nil)
        optionWindow.setContentSize(NSSize(width: AppConstants.Island.width, height: size.height))
    }
}
