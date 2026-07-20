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
            .accessibilityLabel("Send reply")
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
            Text("Reply with your own instruction…")
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
