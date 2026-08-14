// String lookup against this package's catalog.
// Exports: L for HibossIsland user-facing copy.
// Dependencies: Foundation Bundle.module from the package resources.

import Foundation

func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
