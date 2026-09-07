// Loads the copied mixed fixture from the seam spike's resource bundle.
// Exports: FixtureLoader.load().
// Dependencies: Foundation, Bundle.module, and PanelFixture Codable types.

import Foundation

enum FixtureLoader {
    static func load() throws -> PanelFixture {
        guard let url = Bundle.module.url(forResource: "mixed-panel", withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "PanelSeamSpike", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mixed fixture is missing"])
        }
        return try JSONDecoder().decode(PanelFixture.self, from: Data(contentsOf: url))
    }
}
