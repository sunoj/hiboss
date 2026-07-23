// App shell: content area plus the floating rounded tab bar from the design.
// Exports: RootTabView switching Inbox / Messages / Sessions / Settings.
// Dependencies: SwiftUI, the feature views, theme tokens.

import SwiftUI

struct RootTabView: View {
    @ObservedObject var inbox: InboxStore
    @ObservedObject var connection: ConnectionStore
    @State private var selection: Tab = .inbox

    enum Tab: Hashable { case inbox, messages, sessions, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()
            content
            TabBar(selection: $selection, badge: inbox.pendingCount)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .inbox:
            InboxView(store: inbox) { selection = .settings }
        case .messages:
            MessagesView(store: inbox)
        case .sessions:
            SessionsView(store: inbox)
        case .settings:
            SettingsView(connection: connection)
        }
    }
}

private struct TabBar: View {
    @Binding var selection: RootTabView.Tab
    let badge: Int

    var body: some View {
        HStack(spacing: 0) {
            item(.inbox, "line.3.horizontal", "Inbox", badge: badge)
            item(.messages, "bubble.left", "Messages")
            item(.sessions, "chart.bar", "Sessions")
            item(.settings, "gearshape", "Settings")
        }
        .frame(height: 60)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.line2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func item(_ tab: RootTabView.Tab, _ icon: String, _ title: String, badge: Int = 0) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 15, minHeight: 15)
                            .padding(.horizontal, 2)
                            .background(PriorityColor.critical)
                            .clipShape(Capsule())
                            .offset(x: 12, y: -6)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
            }
            .foregroundStyle(selection == tab ? Theme.ink : Theme.ink3)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
