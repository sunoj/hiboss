// Native peer disclosure keeps the transcript reachable and opens the full recent list in a sheet.
// Exports ProjectPeersView with shared local read indicators in both preview and full list.
// Dependencies: RecentProjectPeers, SessionReadIndicator, SwiftUI and Theme.

import SwiftUI

struct ProjectPeersView: View {
    let peers: [RecentProjectPeer]
    @State private var showsAll = false
    @Environment(\.needsYouSessionIDs) private var needsYou

    var body: some View {
        if !peers.isEmpty {
            DisclosureGroup {
                ForEach(RecentProjectPeers.preview(peers)) { peer in row(peer) }
                if peers.count > RecentProjectPeers.previewLimit {
                    Button("Show all") { showsAll = true }.frame(minHeight: ControlMetric.minTap)
                        .accessibilityIdentifier("project-peers-show-all")
                }
            } label: {
                Text("Recent peers").accessibilityIdentifier("project-peers")
            }
            .hbCard()
            .sheet(isPresented: $showsAll) {
                NavigationStack {
                    List(peers) { peer in row(peer) }.listStyle(.insetGrouped)
                        .navigationTitle("Recent peers")
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsAll = false }
                        } }
                }
            }
        }
    }

    private func row(_ peer: RecentProjectPeer) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            ProjectAvatarView(project: peer.session.avatarProject, size: AvatarSize.row)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(verbatim: peer.session.namedLabel).font(.subheadline)
                        .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                    Spacer(minLength: Space.xxs)
                    SessionReadIndicator(sessionID: peer.id, needsYou: needsYou.contains(peer.id))
                    RecordedTimeText(date: peer.activityDate).font(.caption).foregroundStyle(Theme.ink3)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                HStack(spacing: Space.xxs) {
                    if let agent = peer.session.agentName {
                        AgentAvatarView(name: agent, size: AvatarSize.inline)
                        Text(verbatim: agent).font(.caption).lineLimit(1)
                    }
                    if SessionStatus(word: peer.session.status) == .working {
                        Text("Working").font(.caption).foregroundStyle(Theme.positive).lineLimit(1)
                    }
                }
            }
        }.padding(.vertical, Space.xxs).accessibilityElement(children: .combine)
            .accessibilityIdentifier("project-peer-\(peer.id)")
    }
}
