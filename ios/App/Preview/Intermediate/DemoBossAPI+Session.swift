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
        if sessionFetchCount > 0 { try await DemoDelay.wait("TRANSCRIPT_REFRESH") }
        sessionFetchCount += 1
        if sessionFetchCount == 1,
           ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_EMPTY_FAILURE"] == "1" {
            return SessionEventsPage(events: [])
        }
        if sessionFetchCount == 1,
           ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_RECOVERABLE"] == "1" {
            throw HibossAPIError.requestFailed(status: 404, message: "Session not accessible")
        }
        if sessionID == SessionGrouping.directSessionID
            || ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_UNAVAILABLE"] == "1" {
            throw HibossAPIError.requestFailed(status: 404, message: "Session not found")
        }
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
        if sessionFetchCount == 1,
           ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_EMPTY_FAILURE"] == "1" {
            return AsyncThrowingStream {
                $0.finish(throwing: HibossAPIError.requestFailed(status: 503, message: "Stream unavailable"))
            }
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.open)
            let update = Task {
                if sessionFetchCount == 1, DemoDelay.isHeld("TRANSCRIPT_RESYNC") {
                    do { try await DemoDelay.wait("TRANSCRIPT_RESYNC") }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    continuation.yield(.resync)
                    return
                }
                guard DemoDelay.isHeld("TRANSCRIPT_NEWER") else { return }
                do { try await DemoDelay.wait("TRANSCRIPT_NEWER") }
                catch { return }
                guard !Task.isCancelled else { return }
                let message = HistoryMessage(
                    id: "newer-update", body: "A newer release update.\nMore context follows.",
                    direction: "agent_to_boss", status: "delivered", priority: "normal",
                    mode: "async", createdAt: Date().ISO8601Format(), sessionId: sessionID
                )
                messages.append(message)
                if let event = DemoSessionStream.events(for: sessionID, from: messages).last {
                    continuation.yield(.event(event))
                }
            }
            continuation.onTermination = { _ in update.cancel() }
        }
    }
}

// Inventory facts use the same service boundary as production.
extension DemoBossAPI: SessionsServing {
    func projectSessions() async throws -> [ProjectSession] {
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_TRANSCRIPT_UNAVAILABLE"] == "1" { return [] }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_PEERS"] == "1" {
            return DemoProjectPeers.sessions
        }
        return [ProjectSession(id: "sess-deploy", projectId: nil, projectSlug: "hiboss",
                        branch: "release/v2.4",
                        label: "prod-release", host: "Mac mini",
                        agentName: ProcessInfo.processInfo.environment["HIBOSS_DEMO_SESSION_AGENT"]
                            .flatMap { $0.isEmpty ? nil : $0 } ?? "worker-deploy",
                        status: "working", statusText: "Preparing the release",
                        startedAt: Date().addingTimeInterval(-3600).ISO8601Format(),
                        lastSeenAt: Date().addingTimeInterval(-9).ISO8601Format())]
    }
}
