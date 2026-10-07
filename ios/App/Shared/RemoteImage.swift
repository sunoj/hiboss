// AsyncImage presentation with stable geometry, delayed progress and explicit local retry.
// Exports RemoteImage for decision images, feed images, posters and full-screen viewers.
// Dependencies: SwiftUI, PendingStateView, DemoDelay and Theme semantic roles.

import SwiftUI

struct RemoteImage<Content: View>: View {
    let url: URL?
    var compact = false
    var retryIdentifier = "remote-image-retry"
    @ViewBuilder let content: (Image) -> Content
    @State private var attempt = 0
    @State private var released = false

    var body: some View {
        Group {
            if url == nil {
                unavailable
            } else if released {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): content(image)
                    case .failure: unavailable
                    case .empty: waiting
                    @unknown default: unavailable
                    }
                }.id(attempt)
            } else { waiting }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(attempt)") {
            do { try await DemoDelay.wait("MEDIA") }
            catch { return }
            released = true
        }
    }

    private var waiting: some View {
        Group {
            if compact {
                CompactImageWait(onRetry: retry, retryIdentifier: retryIdentifier).id(attempt)
            } else {
                PendingStateView(title: String(localized: "Loading image…"), onRetry: { retry() })
                    .padding(16)
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 4) {
            if !compact {
                Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .font(.hbCallout).foregroundStyle(Theme.ink2)
            }
            Button(action: retry) {
                Label("Retry image", systemImage: "arrow.clockwise")
                    .font(.hbCaption).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(retryIdentifier)
            .accessibilityValue("Image unavailable")
        }
    }

    private func retry() {
        released = false
        attempt += 1
    }
}

struct CompactImageWait: View {
    let onRetry: () -> Void
    var retryIdentifier = "remote-image-retry"
    @State private var slow = false

    var body: some View {
        Group {
            if slow {
                Button(action: onRetry) {
                    Label("Retry image", systemImage: "arrow.clockwise")
                        .font(.hbCaption).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(retryIdentifier)
                .accessibilityValue("Image is still loading")
            } else {
                DelayedProgressView().accessibilityLabel("Loading image…")
            }
        }
        .task {
            do { try await Task.sleep(for: .seconds(8)) }
            catch { return }
            slow = true
        }
    }
}
