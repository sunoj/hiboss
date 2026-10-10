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
    @State private var showsAllPeers = false

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
        .background(TodayStyle.surface)
        .task(id: context.project) {
            box.reset()
            box.project = context.project
            if context.project != nil { await box.refresh() }
        }
        .onChange(of: context.id) { showsAllPeers = false }
        .accessibilityIdentifier("session.inspector")
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Session details")).font(.headline)
                .accessibilityAddTraits(.isHeader).layoutProbe("session.inspector.title")
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
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let recent = SessionPeers.recent(context: context, now: tick.date)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Peers on this project")).font(.headline)
                ForEach(SessionPeers.visible(recent, showAll: showsAllPeers)) { peer in
                    peerRow(peer, now: tick.date)
                }
                if recent.count > SessionPeers.visibleLimit {
                    Button(showsAllPeers ? L("Show less") : L("Show all")) { showsAllPeers.toggle() }
                }
                if recent.isEmpty {
                    Text(L("No other sessions active in the last 24 hours.")).font(.callout)
                }
                Text(L("Peer messages are coordination, never approval."))
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func peerRow(_ peer: SessionPeer, now: Date) -> some View {
        Button { onSession(peer.id) } label: {
            HStack(spacing: 8) {
                ProjectAvatarView(project: peer.session.avatarProject, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: peer.session.namedLabel).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let agent = peer.session.agentName {
                            AgentAvatarView(name: agent, size: 20)
                            Text(verbatim: agent)
                        }
                        Text(L("updated \(AttentionClock.elapsed(since: peer.lastActivity, now: now)) ago"))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).accessibilityIdentifier("session.peer.\(peer.id)")
    }
}
