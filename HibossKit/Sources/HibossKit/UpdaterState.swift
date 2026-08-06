// Sparkle-free bridge the About pane binds to. The macOS executable wires the
// closures + `canCheck` from the real SPUUpdater, keeping HibossKit (and its
// tests) free of the Sparkle dependency.
// Exports: UpdaterState.
// Dependencies: Combine.

import Combine

@MainActor
public final class UpdaterState: ObservableObject {
    /// Sparkle can start a check right now (false while one is in flight, or on
    /// an unbundled dev run where no updater is attached).
    @Published public var canCheck = false
    /// The bundle carries a usable appcast feed and EdDSA public key, so an
    /// updater is attached. False for builds packaged without release settings.
    @Published public var isConfigured = false
    /// Mirrors the updater's "check automatically" preference.
    @Published public var automaticChecks = true

    /// Wired by the executable to `SPUStandardUpdaterController`.
    public var onCheck: () -> Void = {}
    public var onSetAutomatic: (Bool) -> Void = { _ in }

    public init() {}

    public func check() { onCheck() }

    public func setAutomatic(_ enabled: Bool) {
        automaticChecks = enabled
        onSetAutomatic(enabled)
    }
}
