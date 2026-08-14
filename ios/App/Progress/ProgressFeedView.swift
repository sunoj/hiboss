// Progress tab: a native list of progress posts with project filter and pull-to-refresh.
// Exports: ProgressFeedView bound to a ProgressFeedStore.
// Dependencies: SwiftUI, HibossKit, ProgressPostCard, ListStateView.

import HibossKit
import SwiftUI

struct ProgressFeedView: View {
    @ObservedObject var store: ProgressFeedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var opened: ProgressMedia?

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad && store.posts.isEmpty,
            error: store.posts.isEmpty ? store.loadError : nil,
            isEmpty: store.posts.isEmpty,
            emptyIcon: "calendar.day.timeline.leading",
            emptyTitle: String(localized: "No progress yet"),
            emptyDetail: String(localized: "Agents post here with hiboss progress post \"…\" — no push, no inbox."),
            onRetry: { await store.refresh() }
        ) {
            feedList
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Progress")
        .toolbar { filterMenu }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            ProgressVideoPlayback.shared.sceneActive = phase == .active
        }
        .onAppear { ProgressVideoPlayback.shared.feedVisible = true }
        .onDisappear { ProgressVideoPlayback.shared.feedVisible = false }
        .fullScreenCover(item: $opened) { media in
            ProgressMediaViewer(media: media)
                .onAppear { ProgressVideoPlayback.shared.feedVisible = false }
                .onDisappear { ProgressVideoPlayback.shared.feedVisible = true }
        }
    }

    private var feedList: some View {
        List {
            ForEach(store.posts) { post in
                ProgressPostCard(post: post) { opened = $0 }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .onAppear {
                        if post.id == store.posts.last?.id {
                            Task { await store.loadMore() }
                        }
                    }
            }
            if store.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Project", selection: projectFilter) {
                    Text("All projects").tag(nil as String?)
                    ForEach(store.projects) { item in
                        Text("\(item.project) (\(item.count))").tag(item.project as String?)
                    }
                }
            } label: {
                Label(
                    store.selectedProject ?? String(localized: "All projects"),
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            }
            .accessibilityLabel("Filter by project")
        }
    }

    private var projectFilter: Binding<String?> {
        Binding(
            get: { store.selectedProject },
            set: { store.selectProject($0) }
        )
    }
}
