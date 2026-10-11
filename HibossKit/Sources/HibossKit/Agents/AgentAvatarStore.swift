// Account-scoped avatar lookup, refreshed on connection and stream reconnects.
// Exports AgentAvatarStore and an optional SwiftUI environment value.
// Dependencies: Observation, SwiftUI, and the boss agents contract.

import Foundation
import Observation
import SwiftUI

@MainActor @Observable
public final class AgentAvatarStore {
    private var byID: [String: URL] = [:]
    private var byName: [String: URL] = [:]
    @ObservationIgnored private var api: (any AgentsServing)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshVersion = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(agents: [BossAgent] = []) {
        replace(agents)
    }

    public func url(for identity: String) -> URL? {
        byID[identity] ?? byName[identity]
    }

    public func connect(api: (any AgentsServing)?) {
        disconnect()
        self.api = api
        refresh()
    }

    public func disconnect() {
        generation += 1
        task?.cancel()
        task = nil
        api = nil
        byID = [:]
        byName = [:]
    }

    public func refresh() {
        guard let api else { return }
        task?.cancel()
        refreshVersion += 1
        let account = generation
        let version = refreshVersion
        task = Task { [weak self] in
            do {
                let agents = try await api.fetchAgents()
                guard let self, !Task.isCancelled, account == self.generation,
                      version == self.refreshVersion else { return }
                self.replace(agents)
            } catch {
                // Keep this account's last successful lookup until reconnect refresh succeeds.
            }
        }
    }

    private func replace(_ agents: [BossAgent]) {
        var ids: [String: URL] = [:]
        var names: [String: URL] = [:]
        for agent in agents {
            guard let url = agent.avatarURL, url.host != nil, url.user == nil, url.password == nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            ids[agent.id] = url
            names[agent.name] = url
        }
        byID = ids
        byName = names
    }
}

private struct AgentAvatarsKey: EnvironmentKey {
    static let defaultValue: AgentAvatarStore? = nil
}

extension EnvironmentValues {
    public var agentAvatars: AgentAvatarStore? {
        get { self[AgentAvatarsKey.self] }
        set { self[AgentAvatarsKey.self] = newValue }
    }
}
