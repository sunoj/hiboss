// Shared controls and expiry treatment for the macOS decision surface.
// Exports: option rows, reply field, and ExpiryProgress.
// Dependencies: SwiftUI, localized strings, and OptionSurfaceStyle.

import SwiftUI

/// One option in the resolved state: the chosen one animates a checkmark and,
/// a beat later, the "Answered on <device>" attribution fades in.
struct ResolvedOptionRow: View {
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

struct OptionButton: View {
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

struct SkipButton: View {
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
struct ExpiryBand: View {
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

struct ReplyField: View {
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

    /// Drawn by hand because the system placeholder is too dim on the always-black panel.
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
