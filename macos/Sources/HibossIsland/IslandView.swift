// Renders the option picker for island and standard-window presentation.
// Exports: IslandView and OptionSurfaceStyle.
// Dependencies: SwiftUI and OptionFlowStore observation.

import SwiftUI

enum OptionSurfaceStyle: Sendable {
    case island
    case window
}

struct IslandView: View {
    @ObservedObject var flow: OptionFlowStore
    let surfaceStyle: OptionSurfaceStyle
    @State private var replyText = ""

    init(flow: OptionFlowStore, surfaceStyle: OptionSurfaceStyle = .island) {
        self.flow = flow
        self.surfaceStyle = surfaceStyle
    }

    var body: some View {
        if let message = flow.activeMessage {
            VStack(alignment: .leading, spacing: 12) {
                agentHeader(message)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message.body)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        optionList(message)
                        errorLabel
                    }
                }
                ReplyField(text: $replyText, isSubmitting: isSubmitting) {
                    submitReply(for: message.id)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surfaceShape)
            .onChange(of: message.id) { replyText = "" }
        }
    }

    private func agentHeader(_ message: OptionMessage) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(message.agentName ?? "HiBoss")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
            Spacer()
            if case .submitting = flow.presentationState {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            SkipButton { flow.skip() }
                .disabled(isSubmitting)
        }
    }

    private func submitReply(for messageID: MessageID) {
        let pending = replyText
        Task {
            if await flow.submit(pending, for: messageID) { replyText = "" }
        }
    }

    private func optionList(_ message: OptionMessage) -> some View {
        VStack(spacing: 7) {
            ForEach(message.options, id: \.self) { option in
                OptionButton(title: option) {
                    Task { await flow.choose(option, for: message.id) }
                }
                .disabled(isSubmitting)
            }
        }
    }

    @ViewBuilder
    private var errorLabel: some View {
        if case let .failed(message) = flow.presentationState {
            Text(message)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.9))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var surfaceShape: some View {
        switch surfaceStyle {
        case .island:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        case .window:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black)
        }
    }

    private var isSubmitting: Bool {
        if case .submitting = flow.presentationState { return true }
        return false
    }
}

private struct OptionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isHovering ? 0.9 : 0.35)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: 35)
            .background(Color.white.opacity(isHovering ? 0.16 : 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(isHovering ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .accessibilityLabel("Choose \(title)")
    }
}

private struct SkipButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.5))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(isHovering ? 0.16 : 0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("Skip this question")
        .accessibilityLabel("Skip this question")
    }
}

private struct ReplyField: View {
    @Binding var text: String
    let isSubmitting: Bool
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            TextField("Reply with your own instruction…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(canSubmit ? 0.9 : 0.25))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Send reply")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .disabled(isSubmitting)
    }

    private var canSubmit: Bool {
        !isSubmitting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
