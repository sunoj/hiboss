// Measures a fully populated live presentation for existing layout fixture comparisons.
// Exports: OptionPanelLayout test helper; production sizing uses live height preferences.
// Dependencies: SwiftUI hosting and real Today/answerability projection.

import AppKit
import HibossKit
import SwiftUI
@testable import HibossIsland

@MainActor
enum OptionPanelLayout {
    static func expandedHeight(for message: OptionMessage,
                               width: CGFloat = AppConstants.Island.width) -> CGFloat {
        let overview = OverviewStore()
        let question = HistoryMessage(id: message.id, body: message.body, agentName: message.agentName,
            direction: "agent_to_boss", status: "sent", priority: "normal", mode: "blocking",
            metadata: message.metadata, expiresAt: message.expiresAt, createdAt: "2026-10-15T00:00:00Z",
            sessionLabel: message.sessionLabel, sessionBranch: message.sessionBranch)
        overview.update(history: [question], live: nil, now: .now, health: .live(checkedAt: .now),
            coverageComplete: true, requiredInputs: [question], requiredInputLoaded: true)
        var reported: CGFloat?
        let host = NSHostingView(rootView: IslandView(flow: OptionFlowStore(), reply: AttentionReplyState(),
            overview: overview, reportHeight: { _, height in reported = height })
            .frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded()
        let natural = host.fittingSize.height
        host.layoutSubtreeIfNeeded()
        return reported ?? (ceil(natural) + 1)
    }
}
