// Deterministic demo delays for capturing native intermediate states.
// Exports DemoDelay.wait; production operations are unaffected.
// Dependencies: Foundation and the HIBOSS_DEMO launch environment.

import Foundation

enum DemoDelay {
    static func isHeld(_ source: String) -> Bool {
        guard isDemoMode else { return false }
        return (Int(ProcessInfo.processInfo.environment["HIBOSS_DEMO_\(source)_DELAY_MS"] ?? "") ?? 0) > 0
    }

    static func wait(_ source: String) async throws {
        guard isDemoMode else { return }
        let key = "HIBOSS_DEMO_\(source)_DELAY_MS"
        let delay = Int(ProcessInfo.processInfo.environment[key] ?? "") ?? 0
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
    }
}
