// String lookup against this package's catalog.
// Exports: kitL for HibossKit user-facing copy (errors, connection, labels).
// Dependencies: Foundation Bundle.module from the package resources.

import Foundation

func kitL(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
