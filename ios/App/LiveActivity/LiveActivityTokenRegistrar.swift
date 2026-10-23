// Sends decision Live Activity push tokens to the server so it can end them (direct mode only).
// Exports: LiveActivityTokenServing and LiveActivityTokenRegistrar.
// Dependencies: ActivityKit, HibossKit (PushMode, HibossAPI), PushManager. Never logs tokens.

import ActivityKit
import Foundation
import HibossKit
import os

private let tokenLog = Logger(subsystem: "ai.hiboss.app", category: "LiveActivity")

protocol LiveActivityTokenServing: Sendable {
    func registerLiveActivityToken(messageID: String, token: String, environment: String) async throws
}

extension HibossAPI: LiveActivityTokenServing {}

@MainActor
final class LiveActivityTokenRegistrar {
    static let shared = LiveActivityTokenRegistrar()

    var mode: () -> PushMode? = { PushManager.shared.pushMode }
    var api: () -> (any LiveActivityTokenServing)? = { HiBossStore.bossAPI() }
    var environment: () -> String = { PushManager.shared.environment }
    /// Waits before each retry after the first attempt fails.
    var retryDelays: [Duration] = [.seconds(2), .seconds(10), .seconds(60)]
    private var observed: Set<String> = []

    /// Only a server with its own APNs key can push to an activity token; relay mode stays local.
    var pushType: PushType? { mode() == .direct ? .token : nil }

    /// Registers every token the activity reports, once per activity.
    func observe(_ activity: Activity<DecisionActivityAttributes>) {
        guard mode() == .direct, observed.insert(activity.id).inserted else { return }
        let messageID = activity.attributes.messageID
        let activityID = activity.id
        Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.register(token: token, messageID: messageID)
            }
            self?.observed.remove(activityID)
        }
    }

    /// True once the server accepted the token; retries transient failures with backoff.
    /// A client error (409 included) is final for this token only.
    @discardableResult
    func register(token: Data, messageID: String) async -> Bool {
        guard mode() == .direct, let api = api() else { return false }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let environment = environment()
        for delay in [Duration.zero] + retryDelays {
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return false }
            }
            do {
                try await api.registerLiveActivityToken(messageID: messageID, token: hex,
                                                        environment: environment)
                return true
            } catch let HibossAPIError.requestFailed(status, _) where (400..<500).contains(status) {
                tokenLog.error("Live Activity token registration rejected (HTTP \(status))")
                return false
            } catch {
                tokenLog.error("Live Activity token registration failed")
            }
        }
        return false
    }
}
