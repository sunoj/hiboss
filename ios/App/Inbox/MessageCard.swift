// Pending decision card: material tile, agent header, body, inline options, countdown.
// Exports: MessageCard rendering one pending HistoryMessage with reply actions.
// Dependencies: SwiftUI, HibossKit HistoryMessage, priority tokens.

import HibossKit
import SwiftUI

struct MessageCard: View {
    let message: HistoryMessage
    var settlement: DecisionSettlement? = nil
    var onChoose: (String) -> Void
    var onOpen: () -> Void

    private var priority: MessagePriority { message.priorityValue }
    private var options: [String] { message.options }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) { info }
                .buttonStyle(.plain)
            if let settlement {
                settledChoice(settlement)
            } else {
                actions
            }
            if settlement == nil, let defaultOption {
                Label("Auto-selects “\(defaultOption)” on timeout", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20)
                .fill(priority.color)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Header, body, and meta — the tappable path through to detail.
    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(message.body)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            MessageMetaStrip(message: message, density: .selected)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityHint("Opens the decision")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message.avatarInitials)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let session = sessionText {
                    Text(session)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            urgency
        }
    }

    /// Countdown owns the trailing slot; a priority symbol only when it carries meaning.
    private var urgency: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if settlement == nil, let deadline = message.expirationDate {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    CountdownText(deadline: deadline, tint: countdownTint)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if settlement == nil { priorityMark }
        }
    }

    private var countdownTint: Color {
        switch priority {
        case .critical: .red
        case .high: .orange
        default: .secondary
        }
    }

    @ViewBuilder
    private var priorityMark: some View {
        switch priority {
        case .critical:
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Critical")
        case .high:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("High")
        default:
            EmptyView()
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

    private func settledChoice(_ settlement: DecisionSettlement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(settlement.answer, systemImage: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
            if settlement.answeredElsewhere, let source = settlement.sourceLabel {
                Text("Answered on \(source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Answered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        if options.count == 2 {
            HStack(spacing: 8) {
                OptionButton(title: options[0], style: .primary) { onChoose(options[0]) }
                OptionButton(title: options[1], style: .secondary) { onChoose(options[1]) }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    OptionButton(
                        title: option,
                        style: option == defaultOption ? .primary : .secondary,
                        alignment: .leading
                    ) { onChoose(option) }
                }
            }
        }
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
