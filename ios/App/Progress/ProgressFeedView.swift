// Progress tab: a native list of progress posts with project filter and pull-to-refresh.
// Exports: ProgressFeedView bound to a ProgressFeedStore.
// Dependencies: SwiftUI, HibossKit, ProgressPostCard, ListStateView.

import HibossKit
import SwiftUI

struct ProgressFeedView: View {
    @ObservedObject var store: ProgressFeedStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var calendar
    @State private var opened: MediaSession?
    @State private var selectedTag: String?

    private var emptyDetail: String {
        String(localized: "Agents post here with hiboss progress post \"…\" — no push, no inbox.")
    }

    var body: some View {
        Group {
            if store.didLoad {
                feedList
            } else {
                initialState
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Progress")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar { filterMenu }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            ProgressVideoPlayback.shared.sceneActive = phase == .active
        }
        .onAppear { ProgressVideoPlayback.shared.feedVisible = true }
        .onDisappear { ProgressVideoPlayback.shared.feedVisible = false }
        .closesOnRouteTakeover { opened = nil }
        .fullScreenCover(item: $opened) { session in
            MediaViewer(items: session.items, startIndex: session.index)
                .onAppear { ProgressVideoPlayback.shared.feedVisible = false }
                .onDisappear { ProgressVideoPlayback.shared.feedVisible = true }
        }
    }

    private var initialState: some View {
        ListStateView(
            isLoading: !store.didLoad || store.isRefreshing,
            error: store.loadError,
            isEmpty: store.posts.isEmpty,
            emptyIcon: "calendar.day.timeline.leading",
            emptyTitle: String(localized: "No progress yet"),
            emptyDetail: emptyDetail,
            loadingTitle: String(localized: "Loading progress…"),
            onRetry: { await store.retryRefresh() }
        ) {
            feedList
        }
    }

    private var visiblePosts: [ProgressPost] {
        guard let selectedTag else { return store.posts }
        return store.posts.filter { $0.tags.contains(selectedTag) }
    }

    private var tags: [String] {
        Set(store.posts.flatMap(\.tags) + [selectedTag].compactMap { $0 }).sorted()
    }

    private var days: [ProgressDay] {
        let groups = Dictionary(grouping: visiblePosts) { post in
            post.createdDate.map { calendar.startOfDay(for: $0) }
        }
        return groups.map { ProgressDay(date: $0.key, posts: $0.value) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var feedList: some View {
        List {
            if store.loadError != nil, let loadedAt = store.loadedAt {
                retryRow(loadedAt: loadedAt)
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.posts) { post in postRow(post) }
                } header: {
                    dayTitle(day.date)
                        .hbSectionHeader()
                        .textCase(nil)
                        .padding(.leading, Space.m)
                }
            }
            feedTail
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
    }

    private func postRow(_ post: ProgressPost) -> some View {
        ProgressPostCard(post: post, isLiking: store.likingIDs.contains(post.id),
                         likeError: store.likeErrors[post.id], onOpenMedia: { openMedia($0, in: post) }) {
            Task { await store.toggleLike(id: post.id) }
        }
        .listRowInsets(EdgeInsets(top: .zero, leading: Space.m, bottom: Space.s, trailing: Space.m))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func openMedia(_ media: ProgressMedia, in post: ProgressPost) {
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
    }

    private func dayTitle(_ date: Date?) -> Text {
        guard let date else { return Text("Unknown date") }
        if calendar.isDateInToday(date) { return Text("Today") }
        if calendar.isDateInYesterday(date) { return Text("Yesterday") }
        return Text(date, format: .dateTime.day().month(.abbreviated).year())
    }

    private func retryRow(loadedAt: Date) -> some View {
        let time = loadedAt.formatted(date: .omitted, time: .shortened)
        return HStack(spacing: Space.s) {
            Text("Couldn't refresh · showing posts loaded \(time)")
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
                .accessibilityIdentifier("list-stale-banner")
            Spacer(minLength: 0)
            retryButton
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: Space.m, bottom: 0, trailing: Space.m))
    }

    private var retryButton: some View {
        Button("Retry") { Task { await store.retryRefresh() } }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
    }

    @ViewBuilder
    private var feedTail: some View {
        if let error = store.paginationError {
            HStack {
                Text(verbatim: error).font(.footnote).foregroundStyle(Theme.ink2)
                Spacer()
                retryButton
            }
            .listRowSeparator(.hidden)
        } else if store.canLoadMore {
            PendingStateView(title: String(localized: "Loading more progress…"),
                             onRetry: { await store.retryRefresh() })
                .listRowSeparator(.hidden)
                .task(id: store.posts.last?.id) { await store.loadMore() }
        } else if visiblePosts.isEmpty {
            ContentUnavailableView(
                String(localized: "No progress yet"),
                systemImage: "calendar.day.timeline.leading",
                description: selectedTag == nil ? Text(verbatim: emptyDetail) : nil
            )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    @ToolbarContentBuilder
    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Project", selection: projectFilter) {
                    Text("All projects").tag(nil as String?)
                    ForEach(store.projects) { item in
                        Text("\(item.slug) (\(item.count))")
                            .tag(item.slug as String?)
                    }
                }
                if !tags.isEmpty {
                    Divider()
                    Picker("Tags", selection: $selectedTag) {
                        Text("All tags").tag(nil as String?)
                        ForEach(tags, id: \.self) { tag in
                            Text(verbatim: "#\(tag)").tag(tag as String?)
                        }
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
                        Image(systemName: selectedTag == nil
                              ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Filter by project")
            .accessibilityHint("Filter by tag")
        }
    }

    private var projectFilter: Binding<String?> {
        Binding(
            get: { store.selectedProject },
            set: {
                selectedTag = nil
                store.selectProject($0)
            }
        )
    }
}

private struct ProgressDay: Identifiable {
    let date: Date?
    let posts: [ProgressPost]
    var id: Date? { date }
}
