// Home tab view model: loading / error / loaded states and refresh.
// Exports: HomeStore driving the Home dashboard.
// Dependencies: Combine, HibossKit HomeServing.

import Combine
import Foundation
import HibossKit

@MainActor
final class HomeStore: ObservableObject {
    @Published private(set) var dashboard: HomeDashboard?
    @Published private(set) var loadError: String?
    @Published private(set) var didLoad = false

    private var api: (any HomeServing)?
    private var operation: Task<Void, Never>?

    /// True until the first fetch settles — never treat this as "all clear".
    var isLoading: Bool { !didLoad && dashboard == nil }

    /// Fetch failed with nothing to show — distinct from an empty success payload.
    var showsError: Bool { didLoad && dashboard == nil && loadError != nil }

    func start(api: any HomeServing) {
        self.api = api
    }

    func stop() {
        api = nil
        operation?.cancel()
        operation = nil
        dashboard = nil
        loadError = nil
        didLoad = false
    }

    func refresh() async {
        guard api != nil else { return }
        let previous = operation
        let current = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.performRefresh()
        }
        operation = current
        await current.value
    }

    private func performRefresh() async {
        guard let api else { return }
        do {
            let next = try await api.fetchHome()
            guard !Task.isCancelled else { return }
            dashboard = next
            loadError = nil
            didLoad = true
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            didLoad = true
            // Keep any previously loaded dashboard so a transient failure does
            // not blank a populated Home into a false "all clear".
            if dashboard == nil {
                dashboard = nil
            }
        }
    }
}
