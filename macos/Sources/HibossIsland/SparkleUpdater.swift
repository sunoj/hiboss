// Sparkle wiring — kept in the executable so HibossKit stays dependency-free.
// Bridges SPUStandardUpdaterController to the kit's UpdaterState so the About
// pane can drive checks without importing Sparkle.
// Exports: SparkleUpdater.
// Dependencies: Sparkle, Combine, HibossKit.

import Combine
import HibossKit
import Sparkle

@MainActor
final class SparkleUpdater {
    let controller: SPUStandardUpdaterController
    let state = UpdaterState()
    private var cancellables = Set<AnyCancellable>()

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        let updater = controller.updater
        state.automaticChecks = updater.automaticallyChecksForUpdates
        state.onCheck = { [weak controller] in controller?.checkForUpdates(nil) }
        state.onSetAutomatic = { updater.automaticallyChecksForUpdates = $0 }

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak state] canCheck in state?.canCheck = canCheck }
            .store(in: &cancellables)
    }
}
