// Preserves panel values while current relay data is outstanding.
// Exports PanelPendingNotice and the shared iOS freshness presentation predicate.
// Dependencies: SwiftUI, HibossKit, Theme and isolated demo freshness fixtures.

import HibossKit
import SwiftUI

extension PanelFreshness {
    var isPending: Bool {
        switch self {
        case .awaitingData, .stale, .offline: true
        case .live, .task: false
        }
    }
}

@MainActor
func displayedPanelFreshness(_ tile: PanelTile, model: PanelsModel) -> PanelFreshness {
    if isDemoMode {
        switch ProcessInfo.processInfo.environment["HIBOSS_DEMO_PANEL_FRESHNESS"] {
        case "awaiting": return .awaitingData
        case "stale": return .stale
        case "offline": return .offline
        default: break
        }
    }
    return model.freshness(for: tile)
}

struct PanelPendingNotice: View {
    let freshness: PanelFreshness
    let retry: () async -> Void
    @Environment(\.openConnectionSettings) private var openSettings

    var body: some View {
        if freshness.isPending {
            PendingStateView(
                title: String(localized: "Waiting for panel updates…"),
                detail: String(localized: "Current panel data has not arrived. Retry or check Settings."),
                onRetry: retry, onSettings: openSettings
            )
        }
    }
}
