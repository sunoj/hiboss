// First-run main window: pair with a one-time code (or a pasted hiboss://pair link) in place.
// Exports: FirstRunGate, which replaces the workspace while the Mac has no account.
// Dependencies: SwiftUI, AppSettings.needsSignIn, and PairWithCodeSheet (HibossKit redeem).

import HibossKit
import SwiftUI

struct FirstRunGate: ViewModifier {
    @ObservedObject var settings: AppSettings
    let isPreview: Bool
    let onPaired: (ConnectionConfig) -> Void
    let onSettings: () -> Void
    @State private var pairing = false

    func body(content: Content) -> some View {
        if settings.needsSignIn, !isPreview {
            ContentUnavailableView {
                Label(L("Connect to HiBoss"), systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(L("Pair this Mac with a one-time code from a signed-in iPhone or Mac, or paste its hiboss://pair link."))
            } actions: {
                Button(L("Pair with Code…")) { pairing = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("firstRun.pairWithCode")
                    .layoutProbe("firstRun.pairWithCode")
                Button(L("Other Ways to Sign In…"), action: onSettings)
                    .layoutProbe("firstRun.otherWays")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("firstRun.connect")
            .sheet(isPresented: $pairing) {
                PairWithCodeSheet(settings: settings, initialLink: "", onPaired: onPaired)
            }
        } else {
            content
        }
    }
}
