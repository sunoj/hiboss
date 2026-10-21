// Native video controls with persistent playback ownership and explicit loading failures.
// Exports MediaSystemVideo and MediaVideoPlayback for selected-page AVKit playback.
// Dependencies: AVKit, Combine and SwiftUI.

import AVKit
import Combine
import SwiftUI

struct MediaSystemVideo: View {
    let url: URL
    let isPlaying: Bool
    @StateObject private var playback = MediaVideoPlayback()

    var body: some View {
        Group {
            switch playback.state {
            case .loading:
                ProgressView("Loading video…")
            case .ready:
                VideoPlayer(player: playback.player)
            case .unavailable:
                ContentUnavailableView {
                    Label("Video unavailable", systemImage: "video.slash")
                } description: {
                    Text("This video format cannot be played. You can share the original file.")
                }
                .accessibilityIdentifier("media-viewer-video-unavailable")
            }
        }
        .task(id: url) {
            playback.setPlaying(isPlaying)
            await playback.load(url)
        }
        .onChange(of: isPlaying) { _, playing in playback.setPlaying(playing) }
        .onDisappear { playback.setPlaying(false) }
    }
}

@MainActor
final class MediaVideoPlayback: ObservableObject {
    enum State { case loading, ready, unavailable }
    let player = AVPlayer()
    @Published private(set) var state = State.loading
    private var source: URL?
    private var wantsPlayback = false
    private var observation: NSKeyValueObservation?

    func load(_ url: URL) async {
        if source == url, state == .ready {
            setPlaying(wantsPlayback)
            return
        }
        source = url
        observation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .loading
        do {
            let asset = AVURLAsset(url: url)
            let playable = try await asset.load(.isPlayable)
            try Task.checkCancellation()
            guard source == url else { return }
            guard playable else { state = .unavailable; return }
            let item = AVPlayerItem(asset: asset)
            player.replaceCurrentItem(with: item)
            observation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.player.currentItem === item else { return }
                    self.player.pause()
                    self.state = .unavailable
                }
            }
            state = .ready
            setPlaying(wantsPlayback)
        } catch {
            guard !Task.isCancelled, source == url else { return }
            state = .unavailable
        }
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        if playing && state == .ready { player.play() } else { player.pause() }
    }
}
