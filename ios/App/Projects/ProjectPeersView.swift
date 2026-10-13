// Native peer disclosure keeps the transcript reachable and opens the full recent list in a sheet.
// Exports ProjectPeersView; depends on RecentProjectPeers, SwiftUI and Theme.

import SwiftUI

struct ProjectPeersView: View {
    let peers: [RecentProjectPeer]
    @State private var showsAll = false

    var body: some View {
        if !peers.isEmpty {
            DisclosureGroup {
                ForEach(RecentProjectPeers.preview(peers)) { peer in row(peer) }
                if peers.count > RecentProjectPeers.previewLimit {
                    Button("Show all") { showsAll = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("project-peers-show-all")
                }
            } label: {
                Text("Recent peers").accessibilityIdentifier("project-peers")
            }
            .sheet(isPresented: $showsAll) {
                NavigationStack {
                    List(peers) { peer in row(peer) }
                        .navigationTitle("Recent peers")
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsAll = false }
                        } }
                }
            }
        }
    }

    private func row(_ peer: RecentProjectPeer) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProjectAvatarView(project: peer.session.avatarProject, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: peer.session.namedLabel).font(.subheadline)
                if let agent = peer.session.agentName {
                    HStack(spacing: 4) {
                        AgentAvatarView(name: agent, size: 20)
                        Text(verbatim: agent).font(.caption)
                    }
                }
                RecordedTimeText(date: peer.activityDate).font(.caption).foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
            .accessibilityIdentifier("project-peer-\(peer.id)")
    }
}
