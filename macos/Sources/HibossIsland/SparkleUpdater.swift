// Sparkle wiring — kept in the executable so HibossKit stays dependency-free.
// Bridges SPUStandardUpdaterController to the kit's UpdaterState so the About
// pane can drive checks without importing Sparkle. Unconfigured builds (no
// appcast feed / EdDSA key) never start the updater, so they stay silent.
// Exports: SparkleUpdater.
// Dependencies: Sparkle, Combine, HibossKit, os.

import Combine
import HibossKit
import Sparkle
import os

@MainActor
final class SparkleUpdater {
    let controller: SPUStandardUpdaterController
    let state = UpdaterState()
    private var cancellables = Set<AnyCancellable>()
    private static let log = Logger(subsystem: "ai.hiboss.island", category: "updater")

    init() {
        // `startingUpdater: true` runs a modal "The updater failed to start" alert
        // whenever Sparkle rejects the configuration — which is every launch of a
        // build packaged without HIBOSS_APPCAST_URL / HIBOSS_SPARKLE_PUBKEY. Start
        // the updater ourselves so those builds just log instead.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
        )
        let updater = controller.updater
        state.automaticChecks = updater.automaticallyChecksForUpdates
        state.isConfigured = Self.isConfigured

        guard state.isConfigured else {
            Self.log.notice("Sparkle disabled: no appcast feed URL or EdDSA public key in Info.plist")
            return
        }
        do {
            try updater.start()
        } catch {
            state.isConfigured = false
            Self.log.error("Sparkle failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }

        state.onCheck = { [weak controller] in controller?.checkForUpdates(nil) }
        state.onSetAutomatic = { updater.automaticallyChecksForUpdates = $0 }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak state] canCheck in state?.canCheck = canCheck }
            .store(in: &cancellables)
    }

    /// Sparkle needs both an appcast URL and a decodable EdDSA public key; an
    /// empty `SUPublicEDKey` is *invalid* to Sparkle rather than "unset", so
    /// blank values count as missing here too.
    private static var isConfigured: Bool {
        !bundleString("SUFeedURL").isEmpty && !bundleString("SUPublicEDKey").isEmpty
    }

    private static func bundleString(_ key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
