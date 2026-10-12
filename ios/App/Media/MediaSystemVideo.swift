// Native video controls for media destinations that supply item actions.
// Exports MediaSystemVideo; the selected page owns playback through AVKit.
// Dependencies: AVKit and SwiftUI.

import AVKit
import SwiftUI

struct MediaSystemVideo: View {
    let url: URL
    let isPlaying: Bool
    @State private var player: AVPlayer

    init(url: URL, isPlaying: Bool) {
        self.url = url
        self.isPlaying = isPlaying
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { if isPlaying { player.play() } }
            .onChange(of: isPlaying) { _, playing in
                if playing { player.play() } else { player.pause() }
            }
            .onDisappear { player.pause() }
    }
}
