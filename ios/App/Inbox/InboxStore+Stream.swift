// The live boss stream: connection state, reconnect backoff and event delivery.
// Exports: InboxStore.consume, which keeps a failure shown until a reconnect proves itself.
// Dependencies: HibossKit BossServing and HibossAPIError.

import Foundation
import HibossKit

extension InboxStore {
    func consume(_ api: any BossServing) async {
        var failures = 0
        while !Task.isCancelled {
            // Obtaining a stream proves nothing: after a failure, a reconnect counts only
            // once its stream delivers an event or outlives one reconnect delay.
            var retrying = false
            if case .failed = connectionState { retrying = true }
            else if connectionState != .connected { connectionState = .connecting }
            let stream = await api.messageStream()
            let accepted = retrying ? acceptStream() : nil
            if !retrying { connectionState = .connected }
            agentAvatars.refresh()
            var endedCleanly = false
            do {
                for try await event in stream {
                    failures = 0            // a live stream delivering data
                    if connectionState != .connected { connectionState = .connected }
                    handle(event)
                }
                endedCleanly = true
            } catch where !Task.isCancelled {
                accepted?.cancel()
                if (error as? HibossAPIError)?.isAuthFailure == true {
                    // A rejected token won't fix itself — stop reconnecting and
                    // surface it instead of retrying forever every few seconds.
                    rejectAuthorization(error)
                    return
                }
                connectionState = .failed(error.localizedDescription)
            } catch {
                accepted?.cancel()
                return
            }
            accepted?.cancel()
            guard !Task.isCancelled else { return }
            // The server rotates the stream every few minutes: a clean end stays connected
            // and reconnects promptly. Only an error backs off and shows a reconnect state.
            if endedCleanly {
                failures = 0
                connectionState = .connected
                try? await Task<Never, Never>.sleep(for: reconnectDelay)
                continue
            }
            failures += 1
            // Capped exponential backoff so a persistent outage doesn't hammer
            // the server / drain the battery at a fixed cadence.
            let backoff = min(reconnectDelay * (1 << min(failures, 5)), .seconds(60))
            try? await Task<Never, Never>.sleep(for: backoff)
        }
    }

    private func acceptStream() -> Task<Void, Never> {
        Task { [weak self, reconnectDelay] in
            try? await Task<Never, Never>.sleep(for: reconnectDelay)
            guard !Task.isCancelled else { return }
            self?.connectionState = .connected
        }
    }
}
