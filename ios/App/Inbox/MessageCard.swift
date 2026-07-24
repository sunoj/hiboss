// Pending decision card: priority accent, agent header, body, options, countdown.
// Exports: MessageCard rendering one pending HistoryMessage with reply actions.
// Dependencies: SwiftUI, HibossKit HistoryMessage, priority tokens.

import HibossKit
import SwiftUI

struct MessageCard: View {
    let message: HistoryMessage
    var onChoose: (String) -> Void
    var onMore: () -> Void

    private var priority: MessagePriority { message.priorityValue }
    private var options: [String] { message.options }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(message.body)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            metaRow
            actions
            if let defaultOption {
                Label("Auto-selects “\(defaultOption)” on timeout", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                .fill(priority.color)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(message.avatarInitials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(message.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message.metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let session = sessionText {
                    Label(session, systemImage: "square.stack.3d.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            PriorityBadge(priority: priority)
        }
    }

    /// Which session/worktree is asking — critical when several run under one agent.
    private var sessionText: String? {
        for candidate in [message.sessionLabel, message.sessionBranch] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// The option the server auto-selects on timeout, if the asker marked one.
    private var defaultOption: String? {
        guard let value = message.defaultOption?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 12) {
            if let deadline = message.expirationDate {
                Label {
                    CountdownText(deadline: deadline, tint: priority == .critical ? .red : .secondary)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption)
                .foregroundStyle(priority == .critical ? Color.red : .secondary)
            }
            // Blocking/async is the strongest urgency cue — show it independent of
            // the option count (previously hidden once there were >2 options).
            Text(message.mode == "blocking" ? "Blocking" : "Async")
                .font(.caption)
                .foregroundStyle(.secondary)
            if options.count > 2 {
                Text("\(options.count) options")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if options.count == 2 {
            HStack(spacing: 10) {
                OptionButton(title: options[0], style: priority.isUrgent ? .primary : .secondary) {
                    onChoose(options[0])
                }
                OptionButton(title: options[1], style: .secondary) { onChoose(options[1]) }
                if priority.isUrgent {
                    Button(action: onMore) {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    OptionButton(title: option, style: .secondary, alignment: .leading) {
                        onChoose(option)
                    }
                }
            }
        }
    }
}

private struct PriorityBadge: View {
    let priority: MessagePriority

    var body: some View {
        Text(priority.badge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(priority.textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(priority.color.opacity(0.16), in: Capsule())
    }
}

struct OptionButton: View {
    enum Style { case primary, secondary }
    let title: String
    var style: Style = .secondary
    var alignment: Alignment = .center
    var action: () -> Void

    var body: some View {
        Group {
            if style == .primary {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    private var label: some View {
        Text(title)
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}
