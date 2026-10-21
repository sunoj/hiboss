// The always-visible bar of a demo entered from onboarding, and the exit action it shares.
// Exports: DemoExitBar and the `exitDemo` environment action used by Settings.
// Dependencies: SwiftUI and theme tokens.

import SwiftUI

struct DemoExitBar: View {
    let onExit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Demo with sample data", systemImage: "play.rectangle")
                .font(.hbCallout)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("Exit demo", action: onExit)
                .font(.hbBodyStrong)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("demo-exit")
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct ExitDemoKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    /// Set only while a demo entered from onboarding runs.
    var exitDemo: (@MainActor () -> Void)? {
        get { self[ExitDemoKey.self] }
        set { self[ExitDemoKey.self] = newValue }
    }
}
