// Progress tab: a native list of progress posts with project filter and pull-to-refresh.
// Exports: ProgressFeedView bound to a ProgressFeedStore.
// Dependencies: SwiftUI, HibossKit, ProgressPostCard, ListStateView.

import HibossKit
import SwiftUI

struct ProgressFeedView: View {
    @ObservedObject var store: ProgressFeedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var opened: MediaSession?

    var body: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: store.posts.isEmpty,
            emptyIcon: "calendar.day.timeline.leading",
            emptyTitle: String(localized: "No progress yet"),
            emptyDetail: String(
                localized: "Agents post here with hiboss progress post \"…\" — no push, no inbox."),
            loadingTitle: String(localized: "Loading progress…"),
            hasLoaded: store.didLoad,
            onRetry: { await store.retryRefresh() }
        ) {
            feedList
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { filterMenu }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            ProgressVideoPlayback.shared.sceneActive = phase == .active
        }
        .onAppear { ProgressVideoPlayback.shared.feedVisible = true }
        .onDisappear { ProgressVideoPlayback.shared.feedVisible = false }
        .fullScreenCover(item: $opened) { session in
            MediaViewer(items: session.items, startIndex: session.index)
                .onAppear { ProgressVideoPlayback.shared.feedVisible = false }
                .onDisappear { ProgressVideoPlayback.shared.feedVisible = true }
        }
    }

    private var feedList: some View {
        List {
            ForEach(store.posts) { post in
                ProgressPostCard(post: post, isLiking: store.likingIDs.contains(post.id),
                                 likeError: store.likeErrors[post.id], onOpenMedia: { media in
                    let items = post.media.compactMap { media -> MediaItem? in
                        guard let url = URL(string: media.url) else { return nil }
                        return MediaItem(url: url, kind: media.kind == .video ? .video : .image,
                                         title: media.alt, caption: post.body,
                                         aspectRatio: ProgressMediaLayout.clampedAspect(
                                            width: media.width, height: media.height))
                    }
                    if let index = items.firstIndex(where: { $0.url == URL(string: media.url) }) {
                        opened = MediaSession(items: items, index: index)
                    }
                }) {
                    Task { await store.toggleLike(id: post.id) }
                }
                .listRowInsets(EdgeInsets(top: .zero, leading: Space.m, bottom: Space.l, trailing: Space.m))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .onAppear {
                    if post.id == store.posts.last?.id {
                        Task { await store.loadMore() }
                    }
                }
            }
            if store.isLoadingMore {
                PendingStateView(title: String(localized: "Loading more progress…"),
                                 onRetry: { await store.retryRefresh() })
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Project", selection: projectFilter) {
                    Text("All projects").tag(nil as String?)
                    ForEach(store.projects) { item in
                        HStack {
                            ProjectAvatarView(project: item.projectIdentity, size: AvatarSize.compact)
                            Text("\(item.slug) (\(item.count))")
                        }.tag(item.slug as String?)
                    }
                }
            } label: {
                Label {
                    Text(verbatim: store.selectedProject ?? String(localized: "All projects"))
                } icon: {
                    if let slug = store.selectedProject {
                        ProjectAvatarView(project: store.projects.first { $0.slug == slug }?.projectIdentity
                                          ?? .fallback(slug), size: AvatarSize.compact)
                    } else {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .labelStyle(.iconOnly)
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
