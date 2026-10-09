// Supplies explicit synthetic server membership for existing Island rendering fixtures.
// Exports: islandTestOverview; production never derives membership from the option flow.
// Dependencies: Combine, HibossKit, and the native OverviewStore.

import Combine
import HibossKit
@testable import HibossIsland

@MainActor
func islandTestOverview(flow: OptionFlowStore) -> OverviewStore {
    let overview = OverviewStore()
    let inputs = Publishers.CombineLatest(flow.$historyMessages, flow.$activeMessage)
        .map { history, live in
            RequiredInputState(messages: TodayProjection.merge(history: history, live: live),
                ready: true, loaded: true)
        }
        .eraseToAnyPublisher()
    overview.bind(flow: flow, requiredInputs: inputs)
    return overview
}
