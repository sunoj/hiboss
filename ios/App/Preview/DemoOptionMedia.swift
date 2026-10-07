// Optional sample images for exercising Home and message-detail comparisons.
// Exports: DemoOptionMedia.images, enabled only by its screenshot launch flag.
// Dependencies: Foundation environment and HibossKit OptionMedia.

import Foundation
import HibossKit

enum DemoOptionMedia {
    static var images: [OptionMedia] {
        guard ProcessInfo.processInfo.environment["HIBOSS_DEMO_OPTION_MEDIA"] == "1" else { return [] }
        return [
            OptionMedia(label: "Coarse grid", url: "https://picsum.photos/id/1015/900/600"),
            OptionMedia(label: "Fine grid", url: "https://picsum.photos/id/1018/900/600"),
        ]
    }
}
