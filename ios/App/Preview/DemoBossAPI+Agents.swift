// Registered avatar fixture for native demo sessions and history.
// Exports DemoBossAPI.fetchAgents; depends on the shared bundled avatar fixture.

import HibossKit

extension DemoBossAPI {
    func fetchAgents() async throws -> [BossAgent] {
        [AgentAvatarDemo.agent(name: "worker-design")]
    }
}
