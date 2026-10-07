// Demo preference saving with controlled latency and failure, without contacting a server.
// Exports: DemoSettingsPreferencesAPI implementing the same contract as HibossAPI.
// Dependencies: Foundation, HibossKit; enabled only by Settings' demo setup.

import Foundation
import HibossKit

struct DemoSettingsPreferencesAPI: BossPreferencesServing {
    func fetchPreferences() async throws -> BossPreferences { BossPreferences() }

    func updatePreferences(_ preferences: BossPreferences) async throws -> BossPreferences {
        let environment = ProcessInfo.processInfo.environment
        let delay = Int(environment["HIBOSS_DEMO_PREFERENCES_DELAY_MS"] ?? "") ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        if environment["HIBOSS_DEMO_PREFERENCES_FAIL"] == "1" {
            throw URLError(.notConnectedToInternet)
        }
        return preferences
    }
}
