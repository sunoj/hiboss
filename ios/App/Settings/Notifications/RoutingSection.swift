// Routing matrix: which channels fire for each message priority.
// Exports: RoutingSection as a native Form section bound to PreferencesStore.
// Dependencies: SwiftUI, HibossKit, priority tokens.

import HibossKit
import SwiftUI

struct RoutingSection: View {
    @ObservedObject var store: PreferencesStore

    private let priorities: [HibossKit.MessagePriority] = [.critical, .high, .normal, .low]

    var body: some View {
        Section {
            ForEach(priorities, id: \.self) { priority in
                RoutingRow(
                    priority: priority,
                    selected: store.channels(for: priority),
                    onToggle: { store.toggle($0, for: priority) }
                )
            }
        } header: {
            Text("Other channels")
        } footer: {
            Text("Choose Discord, Telegram or API delivery. This doesn’t change who receives messages.")
        }
    }
}

private struct RoutingRow: View {
    let priority: HibossKit.MessagePriority
    let selected: Set<NotificationChannel>
    let onToggle: (NotificationChannel) -> Void

    var body: some View {
        Menu {
            ForEach(NotificationChannel.allCases, id: \.self) { channel in
                Toggle(isOn: binding(channel)) { Text(verbatim: channel.title) }
            }
        } label: {
            LabeledContent {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: summary)
                        .foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(Theme.ink3)
                }
            } label: {
                HStack {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(verbatim: priority.localizedTitle).foregroundStyle(Theme.ink)
                }
            }
        }
        .accessibilityIdentifier("settings-channel-\(priority.rawValue)")
    }

    private var summary: String {
        let names = NotificationChannel.allCases.filter(selected.contains).map(\.title)
        return names.isEmpty ? String(localized: "None") : names.formatted(.list(type: .and, width: .narrow))
    }

    private func binding(_ channel: NotificationChannel) -> Binding<Bool> {
        Binding(get: { selected.contains(channel) }, set: { _ in onToggle(channel) })
    }

    private var dotColor: Color {
        switch priority {
        case .critical: PriorityColor.critical
        case .high: PriorityColor.high
        case .normal: PriorityColor.normal
        case .low: PriorityColor.low
        }
    }
}

extension NotificationChannel {
    var title: String {
        switch self {
        case .discord: "Discord"
        case .telegram: "Telegram"
        case .api: "API"
        }
    }
}
