// Native looping video surface with visible loading, buffering and retry states.
// Exports LoopingPlayerView and its AVPlayer-backed UIKit surface.
// Dependencies: AVFoundation, Combine, SwiftUI, PendingStateView and DemoDelay.

import AVFoundation
import Combine
import SwiftUI

struct LoopingPlayerView: View {
    let url: URL
    var isMuted: Bool
    var isPlaying: Bool
    var fill: Bool
    @State private var presentation = VideoPresentation()
    @State private var released = false
    @State private var attempt = 0

    private var phase: VideoLoadState { presentation.phase }

    var body: some View {
        ZStack {
            if released {
                LoopingPlayerSurface(url: url, isMuted: isMuted, isPlaying: isPlaying,
                                     fill: fill, phase: Binding(get: { phase },
                                        set: { presentation.receive($0) })).id(attempt)
                    .opacity(presentation.hasFrame ? 1 : 0)
                    .allowsHitTesting(false)
            }
            if phase == .loading {
                PendingStateView(title: String(localized: "Loading video…"), onRetry: { retry() })
                    .padding(12).background(.regularMaterial).id(attempt)
            } else if phase == .failed {
                VStack {
                    Text("Video unavailable").font(.hbCallout).foregroundStyle(Theme.ink2)
                    Button("Retry video", action: retry).buttonStyle(.bordered).frame(minHeight: 44)
                }.padding(12).background(.regularMaterial)
            }
        }
        .onChange(of: url) { retry() }
        .task(id: attempt) {
            do { try await DemoDelay.wait("VIDEO") }
            catch { return }
            released = true
        }
    }

    private func retry() {
        presentation.reset()
        released = false
        attempt += 1
    }
}

private struct LoopingPlayerSurface: UIViewRepresentable {
    let url: URL
    let isMuted: Bool
    let isPlaying: Bool
    let fill: Bool
    @Binding var phase: VideoLoadState

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView()
    }

    func updateUIView(_ view: LoopingPlayerUIView, context: Context) {
        view.onStateChange = { phase = $0 }
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
    private var observations: Set<AnyCancellable> = []
    var onStateChange: ((VideoLoadState) -> Void)?

    func load(_ url: URL, fill: Bool) {
        (layer as? AVPlayerLayer)?.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        guard loadedURL != url else { return }
        tearDown()
        loadedURL = url
        let queue = AVQueuePlayer()
        queue.isMuted = true
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        (layer as? AVPlayerLayer)?.player = queue
        observe(queue)
    }

    func setMuted(_ muted: Bool) { player?.isMuted = muted }

    func setPlaying(_ playing: Bool) {
        if playing { player?.play() } else { player?.pause() }
    }

    func tearDown() {
        observations.removeAll()
        player?.pause()
        looper = nil
        player?.removeAllItems()
        player = nil
        loadedURL = nil
        (layer as? AVPlayerLayer)?.player = nil
    }

    private func observe(_ queue: AVQueuePlayer) {
        queue.currentItem?.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] status in
            if status == .failed { self?.onStateChange?(.failed) }
        }.store(in: &observations)
        queue.publisher(for: \.timeControlStatus).receive(on: RunLoop.main).sink { [weak self] status in
            guard let self else { return }
            if status == .waitingToPlayAtSpecifiedRate { onStateChange?(.loading) }
            else if (layer as? AVPlayerLayer)?.isReadyForDisplay == true { onStateChange?(.ready) }
        }.store(in: &observations)
        (layer as? AVPlayerLayer)?.publisher(for: \.isReadyForDisplay).receive(on: RunLoop.main)
            .sink { [weak self] ready in
                if ready { self?.onStateChange?(.ready) }
            }.store(in: &observations)
    }
}
