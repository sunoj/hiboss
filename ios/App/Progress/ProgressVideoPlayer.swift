// One on-screen muted looping AVPlayer for the progress feed.
// Exports: ProgressVideoPlayback, ProgressVideoCell, LoopingPlayerView.
// Dependencies: AVFoundation, SwiftUI, HibossKit ProgressMedia.

import AVFoundation
import Combine
import HibossKit
import SwiftUI
import UIKit

@MainActor
final class ProgressVideoPlayback: ObservableObject {
    static let shared = ProgressVideoPlayback()

    @Published private(set) var activeID: String?
    var feedVisible = false { didSet { republish() } }
    var sceneActive = true { didSet { republish() } }

    private var ratios: [String: CGFloat] = [:]
    var canPlay: Bool { feedVisible && sceneActive }

    func updateVisibility(id: String, ratio: CGFloat) {
        if ratio < 0.35 {
            ratios.removeValue(forKey: id)
        } else {
            ratios[id] = ratio
        }
        republish()
    }

    func clear(_ id: String) {
        ratios.removeValue(forKey: id)
        republish()
    }

    private func republish() {
        let next = canPlay ? ratios.max(by: { $0.value < $1.value })?.key : nil
        if next != activeID { activeID = next }
    }
}

struct ProgressVideoCell: View {
    let media: ProgressMedia
    var onExpand: () -> Void

    @ObservedObject private var playback = ProgressVideoPlayback.shared
    @State private var unmuted = false

    private var videoID: String { media.url }
    private var isActive: Bool { playback.activeID == videoID && playback.canPlay }

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(media.aspectRatio, contentMode: .fit)
            .overlay { poster }
            .overlay {
                if isActive, let url = URL(string: media.url) {
                    LoopingPlayerView(url: url, isMuted: !unmuted, isPlaying: true, fill: true)
                }
            }
            .overlay(alignment: .bottomLeading) { muteBadge }
            .overlay(alignment: .topTrailing) { expandButton }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if isActive { unmuted.toggle() } }
            .background { visibilityProbe }
            .onDisappear {
                playback.clear(videoID)
                unmuted = false
            }
            .accessibilityLabel(media.alt ?? "Video")
            .accessibilityHint("Tap to unmute")
    }

    @ViewBuilder
    private var poster: some View {
        if let poster = media.posterUrl, let url = URL(string: poster) {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    filmPlaceholder
                }
            }
        } else {
            filmPlaceholder
        }
    }

    private var filmPlaceholder: some View {
        Image(systemName: "film").font(.title).foregroundStyle(.secondary)
    }

    private var muteBadge: some View {
        Image(systemName: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            .font(.caption)
            .padding(6)
            .background(.regularMaterial, in: Circle())
            .padding(8)
            .allowsHitTesting(false)
    }

    private var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        }
        .padding(8)
        .accessibilityLabel("Open full screen")
    }

    private var visibilityProbe: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { playback.updateVisibility(id: videoID, ratio: Self.ratio(geo.frame(in: .global))) }
                .onChange(of: geo.frame(in: .global)) { _, frame in
                    playback.updateVisibility(id: videoID, ratio: Self.ratio(frame))
                }
        }
    }

    private static func ratio(_ frame: CGRect) -> CGFloat {
        let visible = frame.intersection(UIScreen.main.bounds)
        guard frame.height > 0, !visible.isNull, !visible.isEmpty else { return 0 }
        return visible.height / frame.height
    }
}

struct LoopingPlayerView: UIViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isPlaying: Bool
    var fill: Bool

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView()
    }

    func updateUIView(_ view: LoopingPlayerUIView, context: Context) {
        view.load(url, fill: fill)
        view.setMuted(isMuted)
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?

    func load(_ url: URL, fill: Bool) {
        (layer as? AVPlayerLayer)?.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        guard loadedURL != url else { return }
        tearDown()
        loadedURL = url
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        (layer as? AVPlayerLayer)?.player = queue
    }

    func setMuted(_ muted: Bool) { player?.isMuted = muted }

    func setPlaying(_ playing: Bool) {
        if playing { player?.play() } else { player?.pause() }
    }

    func tearDown() {
        player?.pause()
        looper = nil
        player?.removeAllItems()
        player = nil
        loadedURL = nil
        (layer as? AVPlayerLayer)?.player = nil
    }
}
