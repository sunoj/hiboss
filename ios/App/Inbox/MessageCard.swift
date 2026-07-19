// Pending decision card: priority band, agent header, body, options, countdown.
// Exports: MessageCard rendering one pending HistoryMessage with reply actions.
// Dependencies: SwiftUI, HibossKit HistoryMessage, and the theme tokens.

import HibossKit
import SwiftUI

struct MessageCard: View {
    let message: HistoryMessage
    var onChoose: (String) -> Void
    var onMore: () -> Void

    private var priority: MessagePriority { message.priorityValue }
    private var options: [String] { message.options }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(priority.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 0) {
                header
                Text(message.body)
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
                metaRow
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                actions
            }
            .padding(.vertical, 13)
            .padding(.trailing, 14)
            .padding(.leading, 13)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(message.avatarInitials)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(uiColor: UIColor(rgb: 0xECEBE7)))
                .frame(width: 26, height: 26)
                .background(Color(uiColor: UIColor(rgb: 0x26221F)))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.line2, lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(message.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(message.metaLine)
                    .font(.hbMonoSmall)
                    .foregroundStyle(Theme.ink3)
            }
            Spacer(minLength: 6)
            Text(priority.badge)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(priority.textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(priority.color.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(priority.color.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 10) {
            if let deadline = message.expirationDate {
                CountdownText(
                    deadline: deadline,
                    tint: priority == .critical ? PriorityColor.critical : Theme.ink2
                )
            }
            Text(optionsHint)
                .font(.hbMonoSmall)
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
        }
    }

    private var optionsHint: String {
        if options.count > 2 { return "\(options.count) options · fanned out" }
        let mode = message.mode == "blocking" ? "◐ blocking" : "○ async"
        return mode
    }

    @ViewBuilder
    private var actions: some View {
        if options.count == 2 {
            HStack(spacing: 8) {
                OptionButton(title: options[0], style: priority.isUrgent ? .primary : .secondary) {
                    onChoose(options[0])
                }
                OptionButton(title: options[1], style: .secondary) { onChoose(options[1]) }
                if priority.isUrgent {
                    Button(action: onMore) {
                        Text("…")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink2)
                            .frame(height: 42)
                            .padding(.horizontal, 12)
                            .background(Theme.surface2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Theme.line2, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
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

struct OptionButton: View {
    enum Style { case primary, secondary }
    let title: String
    var style: Style = .secondary
    var alignment: Alignment = .center
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: style == .primary ? .semibold : .medium))
                .foregroundStyle(style == .primary ? Color.white : Theme.ink)
                .frame(maxWidth: .infinity, alignment: alignment)
                .frame(height: 42)
                .padding(.horizontal, alignment == .leading ? 13 : 0)
                .background(style == .primary ? Theme.positive : Theme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(style == .primary ? .clear : Theme.line2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
