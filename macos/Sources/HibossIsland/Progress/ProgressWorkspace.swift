// Quiet progress timeline with native filters, explicit read states and confirmed deletion.
// Exports: ProgressWorkspace for the main window's Progress destination.
// Dependencies: SwiftUI, HibossKit, ProgressFeedStore and progress media views.

import HibossKit
import SwiftUI

struct ProgressWorkspace: View {
    @ObservedObject var store: ProgressFeedStore
    @State private var opened: ProgressMedia?
    @State private var pendingDelete: ProgressPost?

    var body: some View {
        content
        .workspaceChrome()
        .background(TodayStyle.ground).tint(TodayStyle.live)
        .toolbar {
            filter
            ToolbarItem(placement: .status) {
                CachedReadStatus(isRefreshing: store.isRefreshing, failure: store.loadError,
                    retry: { Task { await store.refresh() } })
            }
            .quietStatusBackground()
        }
        .task { if !store.didLoad { await store.refresh() } }
        .sheet(item: $opened) { ProgressMediaViewer(media: $0) }
        .alert(L("Delete progress post?"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { post in
            Button(L("Delete"), role: .destructive) { Task { await store.delete(id: post.id) } }
            Button(L("Cancel"), role: .cancel) {}
        } message: { _ in Text(L("This post and its media will be removed from the timeline.")) }
        .accessibilityIdentifier("progress.workspace")
    }

    @ViewBuilder
    private var content: some View {
        if store.posts.isEmpty {
            if !store.didLoad {
                ProgressView(L("Loading progress…")).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.loadError, !store.hasResult {
                ContentUnavailableView {
                    Label(L("Progress unavailable"), systemImage: "exclamationmark.triangle")
                } description: { Text(verbatim: error) } actions: {
                    Button(L("Retry")) { Task { await store.refresh() } }
                }
            } else {
                ContentUnavailableView(L("No progress yet"), systemImage: "calendar.day.timeline.leading",
                    description: Text(L("Progress updates from your agents appear here.")))
            }
        } else {
            timeline
        }
    }

    private var timeline: some View {
        List {
            ForEach(store.posts) { post in
                ProgressPostRow(post: post, isLiking: store.likingIDs.contains(post.id),
                    isDeleting: store.deletingIDs.contains(post.id), error: store.actionErrors[post.id],
                    onOpen: { opened = $0 },
                    onLike: { Task { await store.toggleLike(id: post.id) } },
                    onDelete: { pendingDelete = post })
                    .padding(.vertical, 12)
                    .listRowBackground(TodayStyle.surface)
            }
            if store.isLoadingMore { ProgressView(L("Loading more progress…")) }
            if let error = store.pageError { readError(error, retry: { await store.loadMore() }) }
            else if store.nextCursor != nil && !store.isLoadingMore {
                Button(L("Load more")) { Task { await store.loadMore() } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func readError(_ error: String, retry: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(TodayStyle.signal)
            Button(L("Retry")) { Task { await retry() } }
        }
    }

    private var filter: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker(L("Project"), selection: Binding(
                get: { store.selectedProject },
                set: { project in Task { await store.selectProject(project) } }
            )) {
                Text(L("All projects")).tag(nil as String?)
                ForEach(store.projects) { project in
                    HStack {
                        ProjectAvatarView(project: project.projectIdentity, size: 20)
                        Text(verbatim: project.projectIdentity.displayName)
                    }.tag(project.slug as String?)
                }
            }
            .accessibilityLabel(L("Filter by project"))
            .accessibilityIdentifier("progress.project-filter")
        }
    }
}
