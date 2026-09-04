// Resolves HIBOSS_DEMO_* launch flags into a single exclusive deep-link.
// Exports: DemoLaunchRoute and its env parser (used by RootTabView + tests).
// Dependencies: Foundation, HibossKit MessageID.

import Foundation
import HibossKit

/// Screenshot / UI-test deep-links. Exactly one wins; bare `HIBOSS_DEMO=1` is `.none`.
enum DemoLaunchRoute: Equatable {
    case none
    case open(MessageID)
    case notification(MessageID)
    case session(id: String, label: String)
    case resolved

    /// Precedence: NOTIFICATION → OPEN → RESOLVED → SESSION. SESSION must not shadow RESOLVED when
    /// a stale `launchctl setenv HIBOSS_DEMO_SESSION` is still on the simulator —
    /// that leak is what sent every UI test into the prod-release transcript.
    static func resolve(env: [String: String] = ProcessInfo.processInfo.environment) -> DemoLaunchRoute {
        if let id = env["HIBOSS_DEMO_NOTIFICATION_OPEN"], !id.isEmpty {
            return .notification(MessageID(rawValue: id))
        }
        if let id = env["HIBOSS_DEMO_OPEN"], !id.isEmpty {
            return .open(MessageID(rawValue: id))
        }
        if env["HIBOSS_DEMO_RESOLVED"] == "1" {
            return .resolved
        }
        if env["HIBOSS_DEMO_SESSION"] == "1" {
            return .session(id: "sess-deploy", label: "prod-release")
        }
        return .none
    }
}
