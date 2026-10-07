// Optional sample images for exercising Home and message-detail comparisons.
// Exports: DemoOptionMedia.images, enabled only by its screenshot launch flag.
// Dependencies: Foundation environment, bundled PNG resources and HibossKit OptionMedia.

import Foundation
import HibossKit

enum DemoOptionMedia {
    static var images: [OptionMedia] {
        images(enabled: ProcessInfo.processInfo.environment["HIBOSS_DEMO_OPTION_MEDIA"] == "1")
    }

    static func images(enabled: Bool) -> [OptionMedia] {
        guard enabled else { return [] }
        return [
            image(label: "Coarse grid", resource: "demo-coarse-grid"),
            image(label: "Fine grid", resource: "demo-fine-grid"),
        ].compactMap { $0 }
    }

    private static func image(label: String, resource: String) -> OptionMedia? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "png") else { return nil }
        return OptionMedia(label: label, url: url.absoluteString)
    }
}
