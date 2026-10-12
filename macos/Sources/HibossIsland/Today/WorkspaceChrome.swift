// Keeps stationary workspace headings readable beside native scrolling surfaces.
// Exports: workspaceChrome for v4 Box and Progress destinations.
// Dependencies: SwiftUI; newer macOS scroll effects otherwise obscure these headings.

import SwiftUI

extension View {
    @ViewBuilder
    func workspaceChrome() -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}
