// Renders the option picker for island and standard-window presentation.
// Exports: IslandView and OptionSurfaceStyle.
// Dependencies: SwiftUI and OptionFlowStore observation.

import SwiftUI
import HibossKit

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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            islandContent(now: context.date)
        }
    }

    @ViewBuilder
    private func islandContent(now: Date) -> some View {
        if case let .resolved(answer, source) = flow.presentationState, let message = flow.activeMessage {
            resolvedCard(message, answer: answer, source: source)
        } else if let presentation = IslandAttention.presentation(
            live: flow.activeMessage,
            history: flow.historyMessages,
            now: now
        ) {
            let message = presentation.message
            VStack(alignment: .leading, spacing: 12) {
                agentHeader(message, item: presentation.item, now: now)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(message.body)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        optionList(message)
                    }
                }
                errorLabel
                ReplyField(text: $replyText, isSubmitting: isSubmitting) {
                    submitReply(for: message.id)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(surfaceShape)
            .overlay(ExpiryBand(expiresAt: message.expirationDate, surfaceStyle: surfaceStyle))
            .onChange(of: message.id) { replyText = "" }
        }
    }

    /// Shown briefly when the decision was answered on another device.
    private func resolvedCard(_ message: OptionMessage, answer: String?, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectTitle(for: message))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    messageContext(message)
                }
                Spacer()
            }
            Text(message.body)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 7) {
                ForEach(message.options, id: \.self) { option in
                    ResolvedOptionRow(title: option, chosen: option == answer, source: source)
                }
                if let answer, !message.options.contains(answer) {
                    ResolvedOptionRow(title: answer, chosen: true, source: source)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(surfaceShape)
    }

    private func agentHeader(_ message: OptionMessage, item: AttentionItem?, now: Date) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(projectTitle(for: message))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let item, let caption = IslandAttention.autoDecisionCaption(for: item, now: now) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    messageContext(message)
                }
            }
            Spacer()
            if case .submitting = flow.presentationState {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
            if flow.activeMessage?.id == message.id {
                SkipButton { flow.skip() }
                    .disabled(isSubmitting)
            }
        }
    }

    @ViewBuilder
    private func messageContext(_ message: OptionMessage) -> some View {
        if let content = nonEmpty(message.content) {
            Text(content)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        if let agent = nonEmpty(message.agentName), agent != projectTitle(for: message) {
            Text(agent)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
    }

    private func projectTitle(for message: OptionMessage) -> String {
        nonEmpty(message.sessionLabel) ?? nonEmpty(message.sessionBranch) ?? nonEmpty(message.agentName) ?? "HiBoss"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func submitReply(for messageID: MessageID) {
        let pending = replyText
        Task {
            let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            let sent: Bool
            if flow.activeMessage?.id == messageID {
                sent = await flow.submit(pending, for: messageID)
            } else if trimmed.isEmpty {
                sent = false
            } else {
                sent = await flow.answerHistory(trimmed, for: messageID)
            }
            if sent { replyText = "" }
        }
    }

    private func optionList(_ message: OptionMessage) -> some View {
        VStack(spacing: 7) {
            ForEach(message.options, id: \.self) { option in
                OptionButton(title: option, isDefault: option == message.defaultOption) {
                    chooseOption(option, for: message.id)
                }
                .disabled(isSubmitting)
            }
        }
    }

    private func chooseOption(_ option: String, for messageID: MessageID) {
        Task {
            if flow.activeMessage?.id == messageID {
                await flow.choose(option, for: messageID)
            } else {
                await flow.answerHistory(option, for: messageID)
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

/// One option in the resolved state: the chosen one animates a checkmark and,
/// a beat later, the "Answered on <device>" attribution fades in.
private struct ResolvedOptionRow: View {
    let title: String
    let chosen: Bool
    let source: String?
    @State private var showCheck = false
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.green)
                        .scaleEffect(showCheck ? 1 : 0.2)
                        .opacity(showCheck ? 1 : 0)
                }
            }
            if chosen, showSource, let source, !source.isEmpty {
                Text(L("Answered on \(source)"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            chosen ? Color.green.opacity(0.18) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(chosen ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .opacity(chosen ? 1 : 0.38)
        .onAppear {
            guard chosen else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.08)) { showCheck = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.45)) { showSource = true }
        }
    }
}

private struct OptionButton: View {
    let title: String
    var isDefault: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isDefault {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.9)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if isDefault {
                    Text(L("default"))
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isHovering ? 0.9 : 0.35)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(minHeight: 35)
            .background(Color.white.opacity(isHovering ? 0.16 : (isDefault ? 0.14 : 0.09)))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDefault ? 0.35 : 0), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(isHovering ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .accessibilityLabel(isDefault ? L("Choose \(title), default") : L("Choose \(title)"))
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
        .help(L("Skip this question"))
        .accessibilityLabel(L("Skip this question"))
    }
}

/// How much of the expiry band is left, and how alarmed it should look.
/// The band spans the time left when the panel appeared, not the server's original window:
/// delivery lag would otherwise make it drain to zero before the question actually expires.
struct ExpiryProgress: Equatable {
    let startedAt: Date
    let expiresAt: Date

    enum Urgency: Equatable {
        case calm
        case caution
        case urgent
    }

    private static let urgentFraction = 0.15
    private static let cautionFraction = 0.4

    /// 1 when the question is fresh, 0 once it has expired.
    func fraction(at now: Date) -> Double {
        let total = expiresAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 0 }
        return max(0, min(1, expiresAt.timeIntervalSince(now) / total))
    }

    func urgency(at now: Date) -> Urgency {
        let fraction = fraction(at: now)
        if fraction <= Self.urgentFraction { return .urgent }
        if fraction <= Self.cautionFraction { return .caution }
        return .calm
    }
}

/// Drains a stroke around the panel edge as the question approaches its expiry.
private struct ExpiryBand: View {
    let expiresAt: Date?
    let surfaceStyle: OptionSurfaceStyle
    @State private var startedAt = Date()

    private static let lineWidth: CGFloat = 1

    var body: some View {
        if let expiresAt {
            let progress = ExpiryProgress(startedAt: startedAt, expiresAt: expiresAt)
            TimelineView(.animation(minimumInterval: 0.05)) { context in
                let fraction = progress.fraction(at: context.date)
                let color = color(for: progress.urgency(at: context.date))
                band.trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .shadow(color: color.opacity(0.7), radius: 2.5)
                    .padding(Self.lineWidth / 2)
                    .allowsHitTesting(false)
            }
            .onChange(of: expiresAt) { startedAt = Date() }
        }
    }

    private func color(for urgency: ExpiryProgress.Urgency) -> Color {
        switch urgency {
        case .urgent: .red
        case .caution: .orange
        case .calm: .green
        }
    }

    private var band: AnyShape {
        switch surfaceStyle {
        case .island: AnyShape(IslandBandPath(bottomRadius: 24))
        case .window: AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

/// The island's outline minus its top edge, which sits flush against the menu bar.
/// Runs top-left → down → across the bottom → up → top-right, so trimming drains it
/// back toward the top-left corner.
///
/// The corners are true circular arcs, matching the `UnevenRoundedRectangle` that fills
/// the surface. A quadratic curve through the same corner point cuts inside that arc,
/// which let the black fill protrude past this stroke at the bottom corners.
private struct IslandBandPath: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: bottomRadius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: bottomRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct ReplyField: View {
    @Binding var text: String
    let isSubmitting: Bool
    let submit: () -> Void

    /// Recessed, not raised: the option buttons above are the raised surface, so the field
    /// sinks below the panel instead of matching their fill and reading as another button.
    var body: some View {
        HStack(spacing: 7) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .tint(.white.opacity(0.8))
                .onSubmit(submit)
                .overlay(alignment: .leading) { placeholder }
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSubmit ? .white : .white.opacity(0.22))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(L("Send reply"))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .disabled(isSubmitting)
    }

    /// Drawn by hand: the system placeholder takes its color from the effective appearance,
    /// which renders it near-invisible against this always-black panel.
    @ViewBuilder
    private var placeholder: some View {
        if text.isEmpty {
            Text(L("Reply with your own instruction…"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .allowsHitTesting(false)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
    }


    private var canSubmit: Bool {
        !isSubmitting && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
