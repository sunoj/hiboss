// Routing matrix: which channels fire for each message priority.
// Exports: RoutingSection editing PreferencesStore routing per priority.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct RoutingSection: View {
    @ObservedObject var store: PreferencesStore

    private let priorities: [HibossKit.MessagePriority] = [.critical, .high, .normal, .low]

    var body: some View {
        SettingsSection(title: "NOTIFICATION ROUTING") {
            ForEach(Array(priorities.enumerated()), id: \.element) { index, priority in
                if index > 0 { SettingsDivider() }
                RoutingRow(
                    priority: priority,
                    selected: store.channels(for: priority),
                    onToggle: { store.toggle($0, for: priority) }
                )
            }
        }
    }
}

private struct RoutingRow: View {
    let priority: HibossKit.MessagePriority
    let selected: Set<NotificationChannel>
    let onToggle: (NotificationChannel) -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(priority.rawValue.capitalized).font(.hbBody).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(NotificationChannel.allCases, id: \.self) { channel in
                    ChannelChip(
                        channel: channel,
                        isOn: selected.contains(channel),
                        action: { onToggle(channel) }
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

private struct ChannelChip: View {
    let channel: NotificationChannel
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(short)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Color.white : Theme.ink3)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isOn ? Theme.positive : Theme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isOn ? .clear : Theme.line2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var short: String {
        switch channel {
        case .discord: "DC"
        case .telegram: "TG"
        case .api: "API"
        }
    }
}
