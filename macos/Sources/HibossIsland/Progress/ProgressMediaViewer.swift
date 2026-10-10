// Large in-app media sheet with native image sizing and AVKit video playback controls.
// Exports: ProgressMediaViewer; video playback stops when the sheet is dismissed.
// Dependencies: SwiftUI, AVKit, HibossKit ProgressMedia and ProgressRemoteImage.

import AVKit
import HibossKit
import SwiftUI

struct ProgressMediaViewer: View {
    let media: ProgressMedia
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(media.kind == .image ? L("Image") : L("Video")).font(.headline)
                Spacer()
                Button(L("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if media.kind == .image {
                ProgressRemoteImage(url: media.url, alt: media.alt ?? L("Image"))
            } else if failed {
                ContentUnavailableView {
                    Label(L("Video unavailable"), systemImage: "video.slash")
                } actions: {
                    Button(L("Retry")) { attempt += 1 }
                }
            } else if let player {
                VideoPlayer(player: player)
            } else { ProgressView(L("Loading video…")).frame(maxHeight: .infinity) }
            if let alt = media.alt, !alt.isEmpty {
                Text(verbatim: alt).font(.callout).foregroundStyle(TodayStyle.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(20).frame(minWidth: 480, idealWidth: 900, minHeight: 360, idealHeight: 650)
        .background(TodayStyle.surface)
        .task(id: attempt) { await prepareVideo() }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .accessibilityIdentifier("progress.media-viewer")
    }

    private func prepareVideo() async {
        guard media.kind == .video else { return }
        player?.pause()
        player = nil
        failed = false
        guard let url = URL(string: media.url) else {
            failed = true
            return
        }
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable) else {
                failed = true
                return
            }
            try Task.checkCancellation()
            let loaded = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player = loaded
            loaded.play()
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
