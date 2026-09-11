// Fetches new or revised tiles concurrently without mutating live model projections.
// Exports PanelAddition and PanelsModel prefetching; dependencies: Sendable panel API contracts.

import Foundation

struct PanelAddition: Sendable {
    let detail: PanelDetail
    let checkpoint: PanelRelaySnapshot
}

extension PanelsModel {
    func fetchAdditions(_ summaries: [PanelMetadata], service: any PanelsServing) async throws -> [String: PanelAddition] {
        let missing = summaries.filter { summary in
            !tiles.contains { $0.id == summary.panelId && $0.definitionRevision == summary.definitionRevision }
        }
        return try await withThrowingTaskGroup(of: (String, PanelAddition).self) { group in
            var pending = missing.makeIterator()
            // Bound fan-out to six tiles, with detail and checkpoint fetched together.
            for _ in 0..<6 {
                if let summary = pending.next() { group.addTask { try await Self.fetchAddition(summary.panelId, service: service) } }
            }
            var fetched: [String: PanelAddition] = [:]
            for try await (id, addition) in group {
                fetched[id] = addition
                if let summary = pending.next() { group.addTask { try await Self.fetchAddition(summary.panelId, service: service) } }
            }
            return fetched
        }
    }

    private nonisolated static func fetchAddition(_ id: String, service: any PanelsServing) async throws -> (String, PanelAddition) {
        async let detail = service.fetchPanel(id)
        async let checkpoint = service.fetchPanelState(id)
        return try await (id, PanelAddition(detail: detail, checkpoint: checkpoint))
    }
}
