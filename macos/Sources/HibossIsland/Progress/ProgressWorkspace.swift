// Quiet progress timeline with native filters, explicit read states and confirmed deletion.
// Exports: ProgressWorkspace for the main window's Progress destination.
// Dependencies: SwiftUI, HibossKit, ProgressFeedStore and progress media views.

import HibossKit
import SwiftUI

struct ProgressWorkspace: View {
    @ObservedObject var store: ProgressFeedStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var opened: ProgressMedia?
    @State private var pendingDelete: ProgressPost?
    @StateObject private var avatarCache = ProjectAvatarRendererCache()

    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceChrome()
        .background(Color(nsColor: .windowBackgroundColor)).tint(TodayStyle.live)
        .toolbar {
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .automatic)
            }
            ToolbarItem(placement: .primaryAction) {
                if store.hasResult {
                    CachedReadStatus(isRefreshing: store.isRefreshing, failure: store.loadError,
                        retry: { Task { await store.refresh() } })
                }
            }
            .quietStatusBackground()
            filter
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
                        .buttonStyle(.borderedProminent)
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
                    .listRowBackground(Color(nsColor: .controlBackgroundColor))
            }
            if store.isLoadingMore { ProgressView(L("Loading more progress…")) }
            if let error = store.pageError { readError(error, retry: { await store.loadMore() }) }
            else if store.nextCursor != nil && !store.isLoadingMore {
                Button(L("Load more")) { Task { await store.loadMore() } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }

    private func readError(_ error: String, retry: @escaping () async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(TodayStyle.signal)
            Button(L("Retry")) { Task { await retry() } }
        }
    }

    private var filter: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker(selection: Binding(
                get: { store.selectedProject },
                set: { project in Task { await store.selectProject(project) } }
            )) {
                Text(ProgressProjectMenu.allProjectsTitle).tag(nil as String?)
                ForEach(store.projects) { project in
                    ProjectPickerItem(project: project.projectIdentity,
                        title: ProgressProjectMenu.title(for: project), cache: avatarCache,
                        appearance: colorScheme == .dark ? "dark" : "light", scale: displayScale)
                }
            } label: {
                Text(selectedProjectName)
            }
            .pickerStyle(.menu)
            .accessibilityLabel(L("Filter by project"))
            .accessibilityIdentifier("progress.project-filter")
        }
    }

    private var selectedProjectName: String {
        ProgressProjectMenu.collapsedTitle(selectedProject: store.selectedProject, projects: store.projects)
    }
}

enum ProgressProjectMenu {
    static let allProjectsTitle = L("All projects")

    static func title(for project: ProgressProject) -> String {
        project.projectIdentity.displayName
    }

    static func titles(for projects: [ProgressProject]) -> [String] {
        [allProjectsTitle] + projects.map(title(for:))
    }

    static func collapsedTitle(selectedProject: String?, projects: [ProgressProject]) -> String {
        guard let selectedProject else { return allProjectsTitle }
        return projects.first { $0.slug == selectedProject }.map(title(for:)) ?? selectedProject
    }
}

private struct ProjectPickerItem: View {
    let project: ProjectIdentity
    let title: String
    let cache: ProjectAvatarRendererCache
    let appearance: String
    let scale: CGFloat
    @StateObject private var loader = ProjectAvatarLoader()

    var body: some View {
        itemLabel
            .tag(project.slug as String?)
            .task(id: project.avatarURL) { await loader.load(project.avatarURL) }
    }

    @ViewBuilder
    private var itemLabel: some View {
        if let avatar = renderedAvatar {
            Label {
                Text(verbatim: title)
            } icon: {
                avatar
            }
        } else {
            Text(verbatim: title)
        }
    }

    private var renderedAvatar: Image? {
        cache.image(for: project, source: loader.image, appearance: appearance, scale: scale)
            .map(Image.init(nsImage:))
    }
}
