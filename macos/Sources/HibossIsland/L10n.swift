// String lookup for the packaged app or a standalone SwiftPM executable.
// Exports: L for HibossIsland user-facing copy, and the untranslated product name.
// Dependencies: Foundation and the embedded app resource bundle.

import Foundation

/// The product name is a brand, shown as-is in every language.
let productName = "HiBoss" // i18n-exempt: product name, never translated

/// Looks `key` up in this package's catalog. SwiftUI's `LocalizedStringKey` initialisers
/// read `Bundle.main`, which misses the catalog under `swift run`, so views pass `L(...)`.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: appResourceBundle)
}

/// The packaged app embeds the SwiftPM resource bundle; `swift run` and tests use `.module`.
let appResourceBundle: Bundle = {
    if let url = Bundle.main.url(forResource: "HibossIsland_HibossIsland", withExtension: "bundle"), let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()
