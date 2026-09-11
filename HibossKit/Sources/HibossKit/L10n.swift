// Resolves package resources in native app bundles and standalone SwiftPM builds.
// Exports: kitL and kitResourceBundle for localized copy and panel web assets.
// Dependencies: Foundation and the package resource bundle.

import Foundation

func kitL(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: kitResourceBundle)
}

let kitResourceBundle: Bundle = {
    if let url = Bundle.main.url(forResource: "HibossKit_HibossKit", withExtension: "bundle"), let bundle = Bundle(url: url) {
        return bundle
    }
    return .module
}()
