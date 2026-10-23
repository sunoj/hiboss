// Controlled inbox service for coverage, reconnect, and reconciliation tests.
// Exports ControlledInputAPI; holds snapshots and emits ordered live events.
// Dependencies: Foundation and HibossKit service protocols.

import Foundation
import HibossKit

actor ControlledInputAPI: BossServing, RequiredInputServing {
    private var streams: [AsyncThrowingStream<RequiredInputEvent, Error>.Continuation] = []
    private var streamWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var fetchCount = 0
    private var hold = false
    private var heldFetch: CheckedContinuation<[HistoryMessage], Error>?
    private var heldWaiter: CheckedContinuation<Void, Never>?
    private var heldResponse: [HistoryMessage] = []
    private var response: [HistoryMessage] = []
    private var fail = false
    private var failureStatus = 503
    private(set) var replyAttempts = 0
    private var heldReply: CheckedContinuation<ReplyOutcome, Never>?
    private var replyWaiter: CheckedContinuation<Void, Never>?

    private var historyGate: CheckedContinuation<Void, Never>?
    private var historyWaiter: CheckedContinuation<Void, Never>?
    private var holdsHistory = false
    private var historyFails = false
    private(set) var historyReads = 0

    func failHistory() { historyFails = true }
    func holdHistory() { holdsHistory = true }
    func waitForHistory() async {
        if historyGate != nil { return }
        await withCheckedContinuation { historyWaiter = $0 }
    }
    func releaseHistory() {
        historyGate?.resume()
        historyGate = nil
    }

    private var messageStreamEndsCleanly = false
    private var messageStreamFails = false

    func requiredFetchCount() -> Int { fetchCount }

    func setResponse(_ messages: [HistoryMessage]) { response = messages }
    func endMessageStreamsCleanly() { messageStreamEndsCleanly = true }
    func failMessageStreams(_ fails: Bool) { messageStreamFails = fails }
    func failNextFetch(status: Int = 503) {
        fail = true
        failureStatus = status
    }

    func waitForStream(_ index: Int) async {
        if streams.count > index { return }
        await withCheckedContinuation { streamWaiters[index] = $0 }
    }

    func waitForHeldFetch() async {
        if heldFetch != nil { return }
        await withCheckedContinuation { heldWaiter = $0 }
    }

    func holdNextFetch(returning messages: [HistoryMessage]) {
        heldResponse = messages
        hold = true
    }

    func releaseFetch() {
        heldFetch?.resume(returning: heldResponse)
        heldFetch = nil
    }

    func releaseFetchAndHoldNext(returning messages: [HistoryMessage]) {
        releaseFetch()
        holdNextFetch(returning: messages)
    }

    func sendReady(to index: Int) async {
        await send(.ready, to: index)
    }

    func sendReadyBurst(to index: Int) async {
        await waitForStream(index)
        for _ in 0..<10 { streams[index].yield(.ready) }
    }

    func send(_ event: RequiredInputEvent, to index: Int) async {
        await waitForStream(index)
        streams[index].yield(event)
    }

    func disconnect(_ index: Int) { streams[index].finish() }

    func failStream(_ index: Int) {
        streams[index].finish(throwing: URLError(.networkConnectionLost))
    }

    func fetchRequiredInputs() async throws -> [HistoryMessage] {
        fetchCount += 1
        if hold {
            hold = false
            return try await withCheckedThrowingContinuation {
                heldFetch = $0
                heldWaiter?.resume()
                heldWaiter = nil
            }
        }
        if fail {
            fail = false
            throw HibossAPIError.requestFailed(status: failureStatus, message: "Unavailable")
        }
        return response
    }

    func requiredInputStream() async -> AsyncThrowingStream<RequiredInputEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<RequiredInputEvent, Error>.makeStream()
        streams.append(continuation)
        streamWaiters.removeValue(forKey: streams.count - 1)?.resume()
        return stream
    }

    func messageStream() async -> AsyncThrowingStream<BossEvent, Error> {
        if messageStreamEndsCleanly { return AsyncThrowingStream { $0.finish() } }
        if messageStreamFails { return AsyncThrowingStream { $0.finish(throwing: URLError(.cannotConnectToHost)) } }
        return AsyncThrowingStream { $0.onTermination = { _ in } }
    }

    func feedStream() async -> AsyncThrowingStream<HistoryMessage, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func fetchHistory() async throws -> [HistoryMessage] {
        historyReads += 1
        if holdsHistory {
            holdsHistory = false
            await withCheckedContinuation {
                historyGate = $0
                historyWaiter?.resume()
                historyWaiter = nil
            }
        }
        if historyFails { throw URLError(.notConnectedToInternet) }
        return []
    }
    func fetchMessage(_ id: MessageID) async throws -> MessageDetail {
        throw HibossAPIError.requestFailed(status: 404, message: "")
    }
    func waitForHeldReply() async {
        if heldReply != nil { return }
        await withCheckedContinuation { replyWaiter = $0 }
    }

    func releaseReply(_ outcome: ReplyOutcome) {
        heldReply?.resume(returning: outcome)
        heldReply = nil
    }

    func reply(to id: MessageID, with choice: String) async throws -> ReplyOutcome {
        replyAttempts += 1
        return await withCheckedContinuation {
            heldReply = $0
            replyWaiter?.resume()
            replyWaiter = nil
        }
    }
}
