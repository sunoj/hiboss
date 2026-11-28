// Settings › Connection › Signing key: the fingerprint agents pin and the text `hiboss boss trust` reads.
// Exports SettingsSigningKeySection. Dependencies: SwiftUI, UIKit pasteboard, HibossKit signer helpers.

import HibossKit
import SwiftUI
import UIKit

struct SettingsSigningKeySection: View {
    let signer: SecureEnclaveMessageSigner?
    @State private var copied = false

    var body: some View {
        Section {
            if let signer {
                LabeledContent("Fingerprint") {
                    Text(verbatim: signer.fingerprint).font(.body.monospaced()).textSelection(.enabled)
                }
                .accessibilityIdentifier("settings-signing-fingerprint")
                Button(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy key for agents")) { copy(signer) }
                    .accessibilityIdentifier("settings-signing-copy")
            } else {
                Text("This iPhone has no signing key. Pair it with a code to sign its replies.")
                    .foregroundStyle(Theme.ink2)
            }
        } header: {
            Text("Signing key")
        } footer: {
            Text("Agents verify your replies with this key. Compare the fingerprint with the one `hiboss setup` prints, or paste the copied key into `hiboss boss trust`.")
        }
    }

    private func copy(_ signer: SecureEnclaveMessageSigner) {
        guard let text = try? signer.keyText(label: UIDevice.current.name) else { return }
        UIPasteboard.general.string = text
        copied = true
    }
}
