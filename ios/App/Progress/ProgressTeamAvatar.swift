// Circular team avatar with a same-size placeholder so the row never reflows.
// Exports: ProgressTeamAvatar.
// Dependencies: SwiftUI AsyncImage.

import SwiftUI

struct ProgressTeamAvatar: View {
    let urlString: String
    private let size: CGFloat = 40

    var body: some View {
        Color(.tertiarySystemFill)
            .frame(width: size, height: size)
            .overlay { image }
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                }
            }
        }
    }
}
