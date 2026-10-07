// Settings-only wait feedback: context immediately, progress after 300 ms, recovery after eight seconds.
// Exports: SettingsWaitView and SettingsWaitStage; no operation or request is started here.
// Dependencies: SwiftUI, Theme; task cancellation resets feedback when the operation ends.

import SwiftUI

enum SettingsWaitStage: Equatable {
    case context, progress, longWait

    static func at(elapsed: Duration) -> Self {
        if elapsed >= .seconds(8) { return .longWait }
        return elapsed >= .milliseconds(300) ? .progress : .context
    }
}

struct SettingsWaitView: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey = "Close"
    var showsContext = true
    let action: () -> Void
    @State private var stage = SettingsWaitStage.context

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsContext || stage != .context {
                HStack {
                    if stage != .context { ProgressView() }
                    Text(title)
                }
            }
            if stage == .longWait {
                Text("Taking longer than usual. Check your connection.")
                    .foregroundStyle(Theme.ink2)
                Button(actionTitle, action: action)
            }
        }
        .accessibilityIdentifier("settings-wait")
        .task {
            stage = .context
            do {
                try await Task.sleep(for: .milliseconds(300))
                stage = SettingsWaitStage.at(elapsed: .milliseconds(300))
                try await Task.sleep(for: .milliseconds(7_700))
                stage = SettingsWaitStage.at(elapsed: .seconds(8))
            } catch { }
        }
    }
}
