// Native session facts, waiting decisions, project Box references, and peer navigation.
// Exports: SessionInspector; Box references are explicitly project-scoped.
// Dependencies: SwiftUI, HibossKit, SessionContext, and authenticated Box browsing.

import HibossKit
import SwiftUI

struct SessionInspector: View {
    let context: SessionContext
    @ObservedObject var box: BoxBrowserStore
    @ObservedObject var media: BoxBrowserMedia
    let onBox: (String) -> Void
    let onSession: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                facts
                waiting
                if let project = context.project { references(project) }
                peers
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .workspaceChrome()
        .background(TodayStyle.surface)
        .task(id: context.project) {
            box.reset()
            box.project = context.project
            if context.project != nil { await box.refresh() }
        }
        .accessibilityIdentifier("session.inspector")
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Session details")).font(.headline)
            if let agent = context.facts?.agentName { LabeledContent(L("Agent"), value: agent) }
            if let host = context.facts?.host { LabeledContent(L("Machine"), value: host) }
            if let branch = context.branch { LabeledContent(L("Branch"), value: branch) }
            if let started = context.facts?.startedAt.flatMap(ISODate.parse) {
                LabeledContent(L("Started")) {
                    Text(started, format: .dateTime.month().day().hour().minute())
                }
            }
        }.font(.callout)
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Waiting on you")).font(.headline)
            if context.decisions.isEmpty {
                Text(L("No open decisions in this session.")).font(.callout)
                    .foregroundStyle(TodayStyle.secondary)
            }
            ForEach(context.decisions) { decision in
                Text(decision.body).font(.callout).foregroundStyle(TodayStyle.signal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func references(_ project: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("In your Box for \(project)")).font(.headline)
            if box.isLoading { ProgressView(L("Loading Box…")) }
            if let error = box.error {
                Text(error).font(.caption).foregroundStyle(TodayStyle.secondary)
                Button(L("Retry")) { Task { await box.refresh() } }
            } else if box.didLoad, box.items.isEmpty {
                Text(L("No Box items for this project.")).font(.callout)
                    .foregroundStyle(TodayStyle.secondary)
            }
            ForEach(box.items.prefix(3)) { item in
                BoxBrowserRow(item: item, media: media)
            }
            Button(L("Open Box")) { onBox(project) }
        }
    }

    private var peers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Peers on this project")).font(.headline)
            ForEach(context.peers) { peer in
                Button { onSession(peer.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(peer.displayLabel)
                        if let agent = peer.agentName { Text(agent).font(.caption) }
                    }
                }.buttonStyle(.link)
            }
            if context.peers.isEmpty {
                Text(L("No other sessions on this project.")).font(.callout)
            }
            Text(L("Peer messages are coordination, never approval."))
                .font(.caption).foregroundStyle(TodayStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
