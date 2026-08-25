// Home-dashboard HTTP method on HibossAPI (GET /api/boss/home).
// Exports: HibossAPI HomeServing conformance.
// Dependencies: HomeDashboard models and the shared HibossAPI request helpers.

import Foundation

extension HibossAPI: HomeServing {
    public func fetchHome() async throws -> HomeDashboard {
        try await decode(
            HomeDashboard.self,
            from: config.serverURL
                .appendingPathComponent("api")
                .appendingPathComponent("boss")
                .appendingPathComponent("home"),
            context: "home dashboard"
        )
    }
}
