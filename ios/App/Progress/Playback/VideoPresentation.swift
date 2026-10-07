// Tracks native video loading while retaining a displayed frame during buffering.
// Exports VideoLoadState and VideoPresentation for the looping player surface.
// Dependencies: none; retry starts a fresh presentation and clears terminal failure.

enum VideoLoadState: Equatable { case loading, ready, failed }

struct VideoPresentation {
    private(set) var phase: VideoLoadState = .loading
    private(set) var hasFrame = false

    mutating func receive(_ next: VideoLoadState) {
        guard phase != .failed else { return }
        phase = next
        if next == .ready { hasFrame = true }
    }

    mutating func reset() {
        phase = .loading
        hasFrame = false
    }
}
