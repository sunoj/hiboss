// Ways forward on the connect screen for someone without a server yet.
// Exports: ConnectAlternatives (self-hosting guide link and the sample-data demo).
// Dependencies: SwiftUI and theme tokens.

import SwiftUI

struct ConnectAlternatives: View {
    static let selfHostGuide = URL(string: "https://hiboss.org/docs/self-host/")

    let onExploreDemo: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let guide = Self.selfHostGuide {
                Link(destination: guide) {
                    Label("Don't have a server? Set one up", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("connect-self-host")
            }
            Button(action: onExploreDemo) {
                Label("Explore the demo", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("connect-explore-demo")
            Text("The demo uses sample data and never contacts a server.")
                .font(.hbCaption)
                .foregroundStyle(Theme.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .font(.hbCallout)
        .buttonStyle(.borderless)
    }
}
