// String lookup for the packaged app or a standalone SwiftPM executable.
// Exports: L for HibossIsland user-facing copy.
// Dependencies: Foundation and the embedded app resource bundle.

import Foundation

func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: appResourceBundle)
}

private let appResourceBundle: Bundle = {
    if let url = Bundle.main.url(forResource: "HibossIsland_HibossIsland", withExtension: "bundle"), let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()
