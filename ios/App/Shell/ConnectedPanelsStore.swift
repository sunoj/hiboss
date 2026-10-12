// Owns the panel model for a connection independently of the selected tab.
// Exports ConnectedPanelsStore; account changes replace the model and its evidence.
// Dependencies: HibossKit panel services and Combine.

import Combine
import HibossKit

@MainActor
final class ConnectedPanelsStore: ObservableObject {
    @Published private(set) var model = PanelsModel(demoMode: false, autoload: false)
    private var authorizationObservation: AnyCancellable?

    init() {
        authorizationObservation = AccountAuthorization.shared.observe { [weak self] _ in
            self?.stop()
        }
    }

    private var config: ConnectionConfig?
    private var hasStarted = false
    private(set) var startup: Task<Void, Never>?

    func start(config: ConnectionConfig? = nil, api: (any PanelsServing)? = nil) {
        guard !hasStarted || self.config != config else { return }
        startup?.cancel()
        self.config = config
        hasStarted = true
        model = PanelsModel(api: api, configurationProvider: {
            guard let config else { throw PanelClientError.notConfigured }
            return config
        }, autoload: false)
        let model = model
        startup = Task { await model.loadIfNeeded() }
    }

    func stop() {
        startup?.cancel()
        startup = nil
        hasStarted = false
        config = nil
        model = PanelsModel(demoMode: false, autoload: false)
    }
}
