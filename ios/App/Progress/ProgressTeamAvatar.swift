// Circular team avatar with a same-size placeholder so the row never reflows.
// Exports: ProgressTeamAvatar.
// Dependencies: SwiftUI AsyncImage, Theme and the demo-only media delay.

import SwiftUI

struct ProgressTeamAvatar: View {
    let urlString: String
    private let size: CGFloat = 40
    @State private var released = !DemoDelay.isHeld("MEDIA")

    var body: some View {
        Theme.surface2
            .frame(width: size, height: size)
            .overlay { image }
            .clipShape(Circle())
            .accessibilityHidden(true)
            .task {
                do { try await DemoDelay.wait("MEDIA") }
                catch { return }
                released = true
            }
    }

    @ViewBuilder
    private var image: some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            AsyncImage(url: released ? url : nil) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                }
            }
        }
    }
}
