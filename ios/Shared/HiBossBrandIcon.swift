// Shared macOS-style brand artwork for the iOS app and Widget extension.
// Exports: HiBossBrandIcon, rendered consistently at onboarding and Live Activity sizes.
// Dependencies: SwiftUI and the shared HiBossBrandIcon image asset.

import SwiftUI

struct HiBossBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Image("HiBossBrandIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("HiBoss")
            .accessibilityIdentifier("hiboss-brand-icon")
    }
}
