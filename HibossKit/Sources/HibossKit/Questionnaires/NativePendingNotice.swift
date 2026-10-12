// iOS-only pending feedback for shared panel controls and durable questionnaires.
// Exports NativePendingNotice, NativeDelayedProgress and the submission environment value.
// Dependencies: SwiftUI and system semantic colour roles; macOS presentation is unchanged.

#if os(iOS)
import SwiftUI

enum NativePendingTheme {
    static let ink = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
}

struct NativePendingNotice: View {
    let title: String
    var source: PendingNoticeSource = .submission
    var detail: String = kitL("This is taking longer than expected.")
    var retry: (() async -> Void)? = nil
    @State private var visible = false
    @State private var slow = false
    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if visible {
                HStack(alignment: .top) {
                    if !slow { ProgressView() }
                    Text(verbatim: slow ? source.slowTitle : title)
                        .font(.callout).foregroundStyle(NativePendingTheme.secondary)
                }
                if slow {
                    Text(verbatim: detail).font(.callout).foregroundStyle(NativePendingTheme.ink)
                    if let retry {
                        Button {
                            retrying = true
                            Task { await retry(); retrying = false }
                        } label: {
                            HStack {
                                Text(kitL("Retry"))
                                if retrying { NativeDelayedProgress() }
                            }.frame(minHeight: 44)
                        }.buttonStyle(.bordered).disabled(retrying)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                visible = true
                try await Task.sleep(for: .milliseconds(7_700))
                slow = true
            } catch { return }
        }
    }
}

// A permanently reserved status row keeps cached editors still during polling and recovery.
struct NativeRefreshStatus: View {
    let isRefreshing: Bool
    let error: String?
    let title: String
    var source: PendingNoticeSource = .questionnaires
    let retry: () async -> Void
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 44
    @State private var visible = false
    @State private var slow = false
    @State private var retrying = false

    var body: some View {
        Color.clear.frame(height: rowHeight)
            .overlay {
                if error != nil || (isRefreshing && visible) { notice }
            }
        .task(id: isRefreshing) {
            visible = false
            slow = false
            guard isRefreshing else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                visible = true
                try await Task.sleep(for: .milliseconds(7_700))
                slow = true
            } catch { return }
        }
    }

    private var notice: some View {
        HStack {
            ProgressView().opacity(isRefreshing && visible && error == nil ? 1 : 0)
            Text(verbatim: error ?? (slow ? source.slowTitle : title))
                .font(.caption).foregroundStyle(NativePendingTheme.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                retrying = true
                Task { await retry(); retrying = false }
            } label: {
                Text(kitL("Retry questions")).frame(minHeight: 44)
            }.buttonStyle(.borderless).disabled(retrying)
                .opacity(error != nil || slow ? 1 : 0)
                .allowsHitTesting(error != nil || slow)
                .accessibilityHidden(error == nil && !slow)
        }
        .frame(height: rowHeight)
    }
}

struct NativeDelayedProgress: View {
    var active = true
    @State private var visible = false
    var body: some View {
        ProgressView().opacity(active && visible ? 1 : 0).accessibilityHidden(!active || !visible)
            .task(id: active) {
                visible = false
                guard active else { return }
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
                visible = true
            }
    }
}

private struct NativeSubmissionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nativeSubmissionPending: Bool {
        get { self[NativeSubmissionKey.self] }
        set { self[NativeSubmissionKey.self] = newValue }
    }
}
#endif
