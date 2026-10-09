// Session workspace with the complete History stream and a project-scoped inspector.
// Exports: SessionView; compact windows retain the inspector in a native sheet.
// Dependencies: SwiftUI, HibossKit, HistoryView, SessionContext, and BoxBrowserStore.

import HibossKit
import SwiftUI

struct SessionView: View {
    let context: SessionContext
    @ObservedObject var flow: OptionFlowStore
    @ObservedObject var reply: AttentionReplyState
    @ObservedObject var panels: PanelsModel
    @ObservedObject var box: BoxBrowserStore
    @ObservedObject var media: BoxBrowserMedia
    var isPreview = false
    let onBox: (String) -> Void
    let onSession: (String) -> Void
    @State private var showsInspector = false

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HSplitView {
                    thread.frame(minWidth: 360, maxWidth: .infinity)
                    inspector.frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                thread.toolbar {
                    Button(L("Session details"), systemImage: "sidebar.right") { showsInspector = true }
                }
            }
        }
        .sheet(isPresented: $showsInspector) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button(L("Done")) { showsInspector = false } }.padding(12)
                inspector
            }.frame(minWidth: 320, idealWidth: 400, minHeight: 400)
        }
        .task { if !isPreview { await panels.loadIfNeeded() } }
        .background(TodayStyle.ground)
        .accessibilityIdentifier("session.workspace")
    }

    private var thread: some View {
        VStack(spacing: 0) {
            HistoryView(flow: flow, snapshot: context.snapshot, scope: .session(context.id), reply: reply,
                workspaceHeader: SessionHeader(context: context,
                    connection: isPreview ? .connected : flow.connectionState))
            DisclosureGroup(L("Watching")) {
                ScrollView {
                    if let tile = panels.selectedTile, tile.metadata?.sessionId == context.id {
                        DashboardPanelDetail(tile: tile, model: panels).padding(12)
                    } else {
                        DashboardPanelsSection(model: panels, sessionID: context.id).padding(12)
                    }
                }.frame(maxHeight: 260)
            }.padding(.horizontal, 20).padding(.vertical, 8)
            SessionComposer(message: context.newestAgentMessage, reply: reply, onChoose: flow.answer)
        }
    }

    private var inspector: some View {
        SessionInspector(context: context, box: box, media: media,
            onBox: onBox, onSession: onSession)
    }
}
