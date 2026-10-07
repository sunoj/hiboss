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
                    Text(verbatim: title).font(.callout).foregroundStyle(NativePendingTheme.secondary)
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

struct NativeDelayedProgress: View {
    @State private var visible = false
    var body: some View {
        ProgressView().opacity(visible ? 1 : 0).accessibilityHidden(!visible)
            .task {
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
