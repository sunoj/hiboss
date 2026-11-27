// Native workspace navigation: destinations, sessions grouped by state, and history filters.
// Exports: OverviewSidebar with shared snapshot counts and connection recovery.
// Dependencies: SwiftUI, HibossKit, OverviewSnapshot, SidebarSessionGroup.

import HibossKit
import SwiftUI

struct OverviewSidebar: View {
    let snapshot: OverviewSnapshot
    let selection: OverviewDestination
    let historyState: HistoryState
    let connectionState: ConnectionState
    var hasLoadedHistory = false
    var deviceRequestCount = 0
    var watchingCount = 0
    var unreadSessionIDs: Set<String> = []
    let onSelect: (OverviewDestination) -> Void
    let onSettings: () -> Void
    let onRefresh: () -> Void
    var boxScope: BoxBrowserScope = .all
    var boxScopes: AnyView? = nil
    var onSelectBoxScope: (BoxBrowserScope) -> Void = { _ in }
    @Environment(\.projectSessions) private var inventory
    @State private var sessionSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            brand
            List(selection: sidebarSelection) {
                Section(L("Workspace")) {
                    Label(L("Today"), systemImage: "house")
                        .badge(decisionBadge.map { Text(verbatim: $0) })
                        .tag(BoxSidebarSelection.workspace(.today))
                        .accessibilityIdentifier("overview.today")
                    Label(L("Box"), systemImage: "shippingbox")
                        .tag(BoxSidebarSelection.workspace(.box))
                        .accessibilityIdentifier("overview.box")
                    if selection == .box { boxScopes }
                    Label(L("Progress"), systemImage: "play.rectangle")
                        .tag(BoxSidebarSelection.workspace(.progress))
                    Label(L("Watching"), systemImage: "waveform.path.ecg")
                        .badge(watchingCount)
                        .tag(BoxSidebarSelection.workspace(.watching))
                        .accessibilityIdentifier("overview.watching")
                }
                sessions
                Section(L("History")) {
                    categoryRow(.all)
                    categoryRow(.completed)
                    Label(L("Device Requests"), systemImage: "desktopcomputer.and.arrow.down")
                        .badge(deviceRequestCount)
                        .tag(BoxSidebarSelection.workspace(.deviceRequests))
                        .accessibilityIdentifier("overview.deviceRequests")
                }
                if let notice { connectionNotice(notice).selectionDisabled() }
            }
            .listStyle(.sidebar)
        }
        .accessibilityIdentifier("overview.sidebar")
    }

    private var sidebarSelection: Binding<BoxSidebarSelection> {
        Binding(get: { .selected(selection, scope: boxScope) }, set: { value in
            switch value {
            case let .workspace(destination): onSelect(destination)
            case let .scope(scope): onSelectBoxScope(scope)
            }
        })
    }

    var decisionBadge: String? {
        guard snapshot.answerability.isLoaded, !snapshot.today.decisions.isEmpty else { return nil }
        return snapshot.today.decisions.count.formatted()
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIdentity.icon)
                .resizable().frame(width: 24, height: 24)
            Text(verbatim: "HiBoss").font(.title2.weight(.bold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    private func categoryRow(_ category: OverviewCategory) -> some View {
        HStack(spacing: 8) {
            Label(category.title, systemImage: category.symbol)
            Spacer(minLength: 4)
            Text(verbatim: countsAvailable ? snapshot.count(category).formatted() : "—")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .tag(BoxSidebarSelection.workspace(.category(category)))
        .accessibilityIdentifier("overview.\(category.rawValue)")
    }

    /// One search field over every session, then a header row per state in the server's order.
    /// Headers are rows, not `Section`s: see `SidebarSessionRow`.
    private var sessions: some View {
        let groups = sessionGroups
        return Section {
            SessionSearchField(text: $sessionSearch)
                .accessibilityIdentifier("overview.sessionSearch")
                .selectionDisabled()
            if groups.isEmpty {
                Text(sessionSearch.isEmpty ? L("Your sessions will appear here.") : L("No matching sessions"))
                    .font(.callout).foregroundStyle(.secondary).selectionDisabled()
            }
            ForEach(SidebarSessionRow.rows(groups)) { row in
                switch row {
                case let .header(group):
                    Text(verbatim: group.title)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("overview.sessions.\(group.id)")
                        .selectionDisabled()
                case let .session(session):
                    sessionRow(session).tag(BoxSidebarSelection.workspace(.session(session.id)))
                }
            }
        }
    }

    private var sessionGroups: [SidebarSessionGroup] {
        SidebarSessionGroup.groups(snapshot.today.sessionDirectory, query: sessionSearch) { session in
            inventory.first { $0.id == session.id }?.namedLabel ?? session.projectLabel
        }
    }

    var countsAvailable: Bool { hasLoadedHistory || historyState == .loaded || !snapshot.history.isEmpty }

    private var notice: String? {
        if case let .failed(error) = historyState { return error }
        switch connectionState {
        case .disconnected: return L("Connect to receive agent messages.")
        case .failed: return L("Connection interrupted. Showing recent messages.")
        case .connecting: return L("Connecting…")
        case .connected: return nil
        }
    }

    private func connectionNotice(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if connectionState == .disconnected {
                Button(L("Settings"), action: onSettings)
            } else {
                Button(L("Try again"), action: onRefresh)
            }
        }.padding(.vertical, 8)
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        let fact = inventory.first { $0.id == session.id }
        let text = SidebarSessionText(session: session, facts: fact)
        let project = fact?.avatarProject ?? ProjectIdentity(id: session.id,
            slug: session.projectLabel, displayName: session.projectLabel)
        return HStack(spacing: 8) {
            ProjectAvatarView(project: project, size: 28)
            SidebarSessionIndicator(needsYou: session.needsYou,
                unread: unreadSessionIDs.contains(session.id)).view(sessionID: session.id)
                .layoutProbe("sidebar.dotSlot.\(session.id)")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(verbatim: text.label).lineLimit(1).truncationMode(.tail)
                        .layoutProbe("sidebar.label.\(session.id)")
                    if let nickname = text.nickname {
                        Text(verbatim: nickname).lineLimit(1).fixedSize()
                            .layoutPriority(1).layoutProbe("sidebar.nickname.\(session.id)")
                    }
                }
                HStack(spacing: 4) {
                    if let agent = session.agentName {
                        AgentAvatarView(name: agent, size: 20)
                        Text(verbatim: text.agent ?? agent)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            .truncationMode(.tail)
                            .layoutProbe("sidebar.agent.\(session.id)")
                    }
                    if session.hasLiveWork(now: snapshot.now) {
                        SidebarWorkingCaption().layoutProbe("sidebar.working.\(session.id)")
                    }
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .layoutProbe("sidebar.session.\(session.id)")
        .help(text.fullDescription)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([text.fullDescription,
            SidebarSessionIndicator(needsYou: session.needsYou,
                unread: unreadSessionIDs.contains(session.id)).label,
            session.hasLiveWork(now: snapshot.now) ? L("Working now") : ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
