// Session replay and connection delays for deterministic transcript demo captures.
// Exports DemoBossAPI SessionStreamServing conformance methods.
// Dependencies: HibossKit, DemoSessionStream and DemoDelay.

import HibossKit
import Foundation

extension DemoBossAPI {
    func fetchSessionEvents(
        sessionID: String,
        after: Int?,
        limit: Int
    ) async throws -> SessionEventsPage {
        try await DemoDelay.wait("TRANSCRIPT")
        sessionFetchCount += 1
        let all = DemoSessionStream.events(for: sessionID, from: messages)
        let backfill = ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_EARLIER_DELAY_MS"]
        if backfill?.isEmpty == false {
            if sessionFetchCount == 1 {
                return SessionEventsPage(events: Array(all.suffix(2)), nextAfter: nil, resync: false)
            }
            try await DemoDelay.wait("TRANSCRIPT_EARLIER")
        }
        let start = (after ?? -1) + 1
        let slice = all.filter { $0.sequence >= start }.prefix(limit)
        let events = Array(slice)
        return SessionEventsPage(
            events: events,
            nextAfter: events.last?.sequence,
            resync: false
        )
    }

    func sessionEventStream(
        sessionID: String,
        after: Int
    ) async -> AsyncThrowingStream<SessionStreamFrame, Error> {
        try? await DemoDelay.wait("TRANSCRIPT_CONNECTION")
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { _ in }
        }
    }
}
