// One on-screen muted looping AVPlayer for the progress feed.
// Exports ProgressVideoPlayback and ProgressVideoCell with posters retained during buffering.
// Dependencies: SwiftUI, HibossKit ProgressMedia, RemoteImage and LoopingPlayerView.

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
        Theme.surface2
            .overlay { poster }
            .overlay { activePlayer }
            .overlay(alignment: .bottomLeading) { muteButton }
            .overlay(alignment: .bottomTrailing) { durationPill }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .background { visibilityProbe }
            .onDisappear {
                playback.clear(videoID)
                unmuted = false
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(media.alt ?? String(localized: "Video"))
            .accessibilityHint(String(localized: "Open full screen"))
            .accessibilityAction(.default, onExpand)
            .accessibilityIdentifier("progress-video")
    }

    @ViewBuilder
    private var activePlayer: some View {
        if isActive, let url = URL(string: media.url) {
            LoopingPlayerView(url: url, isMuted: !unmuted, isPlaying: true, fill: true)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let poster = media.posterUrl, let url = URL(string: poster) {
            RemoteImage(url: url, compact: true) { image in
                    image.resizable().scaledToFill()
            }
            .allowsHitTesting(false)
        } else {
            filmPlaceholder
        }
    }

    private var filmPlaceholder: some View {
        Image(systemName: "film").font(.title).foregroundStyle(.secondary)
    }

    private var muteButton: some View {
        Button { unmuted.toggle() } label: {
            Image(systemName: unmuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.body)
                .padding(8)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .accessibilityLabel(unmuted ? String(localized: "Mute") : String(localized: "Unmute"))
    }

    @ViewBuilder
    private var durationPill: some View {
        if let ms = media.durationMs {
            Text(verbatim: ProgressMediaLayout.durationLabel(milliseconds: ms))
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var visibilityProbe: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    playback.updateVisibility(id: videoID, ratio: Self.ratio(geo.frame(in: .global)))
                }
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
