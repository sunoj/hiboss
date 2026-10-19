// Shared native like control and inline mutation feedback.
// Observes BoxStore so detail, rows and viewer reflect the same item state.
import HibossKit
import SwiftUI

struct BoxLikeButton: View {
    let item: BoxItem
    @ObservedObject var store: BoxStore

    var body: some View {
        Button {
            Task { await store.toggleLike(item) }
        } label: {
            Label(item.liked ? String(localized: "Unlike") : String(localized: "Like"),
                  systemImage: item.liked ? "heart.fill" : "heart")
        }
        .disabled(store.organizing.contains(item.id))
        .accessibilityIdentifier("box-like")
    }
}

struct BoxOrganizationError: View {
    @ObservedObject var store: BoxStore

    var body: some View {
        if let error = store.organizationError {
            Text(verbatim: error).font(.callout).foregroundStyle(Theme.negative)
                .accessibilityIdentifier("box-organization-error")
        }
    }
}
