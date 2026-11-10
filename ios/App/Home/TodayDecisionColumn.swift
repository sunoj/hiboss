// Today's detail column beside the decision cards when the window is wide.
// Exports: TodayDecisionColumn (the selected decision or a prompt) and View.handsOffDecision(...).
// Dependencies: SwiftUI, HibossKit, MessageDetailView and SessionMessagesView.

import HibossKit
import SwiftUI

struct TodayDecisionColumn: View {
    let inbox: InboxStore
    let decisionID: MessageID?
    let sessionAPI: (any SessionStreamServing)?
    let panels: PanelsModel

    var body: some View {
        NavigationStack {
            Group {
                if let decisionID {
                    MessageDetailView(store: inbox, messageID: decisionID)
                } else {
                    ContentUnavailableView(
                        "Select a decision", systemImage: "checklist",
                        description: Text("Its details open here.")
                    ).accessibilityIdentifier("today-detail-placeholder")
                }
            }
            .navigationDestination(for: SessionRoute.self) {
                SessionMessagesView(route: $0, api: sessionAPI, store: inbox, panels: panels)
            }
        }
        // A new decision starts a fresh stack rather than inheriting the last one's pushed session.
        .id(decisionID)
    }
}

/// Moves the open decision between Today's sheet (one column) and the detail column (two),
/// so a rotation or fold keeps it on screen.
private struct DecisionHandoff: ViewModifier {
    let isSplit: Bool
    @Binding var decisionID: MessageID?
    @Binding var showingDecision: Bool
    @Binding var columnDecision: MessageID?

    func body(content: Content) -> some View {
        content
            .onChange(of: isSplit) { _, split in
                if split {
                    columnDecision = showingDecision ? decisionID : nil
                    showingDecision = false
                } else if let columnDecision {
                    decisionID = columnDecision
                    showingDecision = true
                }
            }
            // Split, a card's open request lands in the column; the sheet never presents.
            .onChange(of: showingDecision) { _, showing in
                guard isSplit, showing else { return }
                columnDecision = decisionID
                showingDecision = false
            }
    }
}

extension View {
    func handsOffDecision(isSplit: Bool, decisionID: Binding<MessageID?>, showingDecision: Binding<Bool>,
                          columnDecision: Binding<MessageID?>) -> some View {
        modifier(DecisionHandoff(isSplit: isSplit, decisionID: decisionID, showingDecision: showingDecision,
                                 columnDecision: columnDecision))
    }
}
