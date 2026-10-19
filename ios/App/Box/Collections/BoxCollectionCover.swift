// Loads collection covers by ID, including items outside the browser's loaded pages.
// Uses the existing authenticated item and media API, with an explicit retry on failure.
import HibossKit
import SwiftUI

struct BoxCollectionCover: View {
    let id: String
    let api: (any BoxServing)?
    @ObservedObject var media: BoxMediaStore
    @State private var item: BoxItem?
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        Group {
            if let item { BoxThumbnail(item: item, media: media) }
            else if let error {
                VStack {
                    Text(verbatim: error).font(.caption)
                    RetryButton { retry += 1 }
                }
            } else { ProgressView().accessibilityLabel("Loading Box media…") }
        }
        .task(id: id + String(retry)) {
            guard let api = api as? any BoxCollectionServing else { return }
            do {
                item = try await api.boxItem(id: id)
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
