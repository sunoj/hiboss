// Locates and decodes the two repository panel fixtures without copying them.
// Exports: FixtureLoader.load(name:).
// Dependencies: Foundation, JSONValue Codable, and repository-relative paths.

import Foundation

enum FixtureLoader {
    static let names = ["metric-panel.json", "rollout-decision.json"]

    static func load(name: String) throws -> PanelFixture {
        let data = try Data(contentsOf: locate(name: name))
        return try JSONDecoder().decode(PanelFixture.self, from: data)
    }

    static func locate(name: String) throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("panel-runtime/fixtures/\(name)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw NSError(domain: "PanelSwiftUISpike", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not found: \(name)"])
    }
}
