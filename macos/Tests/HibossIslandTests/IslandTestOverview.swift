// Supplies explicit synthetic server membership for existing Island rendering fixtures.
// Exports: islandTestOverview; production never derives membership from the option flow.
// Dependencies: Combine, HibossKit, and the native OverviewStore.

import Combine
import HibossKit
@testable import HibossIsland

@MainActor
func islandTestOverview(flow: OptionFlowStore) -> OverviewStore {
    let overview = OverviewStore()
    let inputs = Publishers.CombineLatest3(
        flow.$historyMessages, flow.$activeMessage, flow.$presentationState)
        .map { history, live, state in
            let resolvedID: MessageID?
            if case .resolved = state { resolvedID = live?.id } else { resolvedID = nil }
            let messages = TodayProjection.merge(history: history, live: live).filter { $0.id != resolvedID }
            return RequiredInputState(messages: messages,
                ready: true, loaded: true)
        }
        .eraseToAnyPublisher()
    overview.bind(flow: flow, requiredInputs: inputs)
    return overview
}
