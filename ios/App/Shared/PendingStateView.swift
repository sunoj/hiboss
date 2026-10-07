// Native pending presentation with delayed progress and a continuous eight-second deadline.
// Exports PendingStateView, PendingRows, DelayedProgressView and RetryButton.
// Dependencies: SwiftUI, Theme semantic roles; callers retain their cached content.

import SwiftUI

enum PendingTiming {
    static let revealDelay: Duration = .milliseconds(300)
    static let escalationDelay: Duration = .milliseconds(7_700)
}

struct PendingStateView: View {
    let title: String
    var detail: String? = nil
    var showsPlaceholder = false
    var escalated = false
    var statusIdentifier = "pending-status"
    var onRetry: (() async -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @State private var visible = false
    @State private var slow = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if visible || escalated {
                HStack(alignment: .top, spacing: 8) {
                    if !slow && !escalated { ProgressView().tint(Theme.ink2) }
                    Text(verbatim: title).font(.hbCallout).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier(statusIdentifier)
                if slow || escalated { escalation }
                if showsPlaceholder { PendingRows() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            do {
                try await Task.sleep(for: PendingTiming.revealDelay)
                visible = true
                try await Task.sleep(for: PendingTiming.escalationDelay)
                slow = true
            } catch { return }
        }
    }

    private var escalation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: detail ?? String(localized: "This is taking longer than expected."))
                .font(.hbCallout).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pending-escalation")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if let onRetry { RetryButton(action: onRetry) }
        if let onSettings {
            Button("Settings", action: onSettings).buttonStyle(.bordered).frame(minHeight: 44)
        }
    }
}

struct PendingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Loading…").font(.hbCaption)
                    Text("Checking your attention queue").font(.hbH2)
                    Text("Loading…").font(.hbCallout)
                }
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(Theme.ink2)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .accessibilityIdentifier("pending-rows")
    }
}

struct DelayedProgressView: View {
    var tint: Color = Theme.ink
    @State private var visible = false

    var body: some View {
        ProgressView().tint(tint)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
            .task {
                do { try await Task.sleep(for: PendingTiming.revealDelay) }
                catch { return }
                visible = true
            }
    }
}

struct RetryButton: View {
    let action: () async -> Void
    @State private var retrying = false

    var body: some View {
        Button {
            retrying = true
            Task { await action(); retrying = false }
        } label: {
            HStack {
                Text("Retry")
                if retrying { DelayedProgressView() }
            }.frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(retrying)
        .accessibilityIdentifier("pending-retry")
    }
}

private struct ConnectionSettingsKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
    var openConnectionSettings: @MainActor @Sendable () -> Void {
        get { self[ConnectionSettingsKey.self] }
        set { self[ConnectionSettingsKey.self] = newValue }
    }
}
