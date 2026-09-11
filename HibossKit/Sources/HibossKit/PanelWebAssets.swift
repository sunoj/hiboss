// Loads the self-contained display-only panel document from package resources.
// Exports: PanelWebAssets.document.
// Dependencies: Foundation kitResourceBundle and the PanelWeb/index.html resource.

import Foundation

enum PanelWebAssets {
    static var document: String {
        guard let url = kitResourceBundle.url(forResource: "index", withExtension: "html") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
