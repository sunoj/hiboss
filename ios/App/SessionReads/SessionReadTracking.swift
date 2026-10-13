// Marks a transcript read on entry and while visible with an active app scene.
// Exports SessionReadTracking; observes both history refreshes and live transcript events.
// Dependencies: SwiftUI, InboxStore, SessionReadStore and HibossKit session events.

import HibossKit
import SwiftUI

struct SessionReadTracking: ViewModifier {
    @EnvironmentObject private var reads: SessionReadStore
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var inbox: InboxStore
    let sessionID: String
    let events: [SessionEvent]
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                visible = true
                markRead()
            }
            .onDisappear { visible = false }
            .onChange(of: scenePhase) { _, _ in updateVisibleRead() }
            .onChange(of: inbox.history) { _, _ in updateVisibleRead() }
            .onChange(of: events) { _, _ in updateVisibleRead() }
            .onChange(of: reads.baseline) { _, _ in updateVisibleRead() }
    }

    private func updateVisibleRead() {
        guard visible, scenePhase == .active else { return }
        markRead()
    }

    private func markRead() {
        reads.markRead(sessionID, messages: inbox.history, events: events)
    }
}
