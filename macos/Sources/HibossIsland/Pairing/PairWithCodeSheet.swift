// Native sheet that redeems a one-time pairing code after the boss confirms the server host.
// Exports: PairWithCodeSheet.
// Dependencies: SwiftUI, AppSettings.pair(with:), and PairWithCodeForm.

import HibossKit
import SwiftUI

struct PairWithCodeSheet: View {
    @ObservedObject var settings: AppSettings
    let onPaired: (ConnectionConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var form: PairWithCodeForm
    @State private var isRedeeming = false
    @State private var failure: String?

    init(settings: AppSettings, initialLink: String, onPaired: @escaping (ConnectionConfig) -> Void) {
        self.settings = settings
        self.onPaired = onPaired
        _form = State(initialValue: PairWithCodeForm(link: initialLink))
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Pairing link"), text: $form.link, prompt: Text(verbatim: "hiboss://pair?…"))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: form.link) { form.applyLink() }
            } header: {
                Text(L("Paste a link"))
            } footer: {
                Text(L("On a signed-in iPhone or Mac, open Pair another device and copy its link."))
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField(L("Server URL"), text: $form.server)
                    .font(.system(.body, design: .monospaced))
                TextField(L("Pairing code"), text: $form.code, prompt: Text(verbatim: "hb_pair_…"))
                    .font(.system(.body, design: .monospaced))
                TextField(L("Device label"), text: $settings.deviceLabel)
            } header: {
                Text(L("Or type the server and code"))
            }

            confirmSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 500)
        .disabled(isRedeeming)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { Task { await redeem() } }
                    .disabled(form.payload == nil || isRedeeming)
            }
        }
    }

    private var confirmSection: some View {
        Section {
            LabeledContent(L("Server")) {
                Text(form.payload?.serverHost ?? "—") // i18n-exempt: placeholder dash
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let issue = form.issue {
                Label(issue.localizedDescription, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            if let failure {
                Label(failure, systemImage: "xmark.octagon")
                    .foregroundStyle(.secondary)
            }
            if isRedeeming {
                ProgressView(L("Pairing…")).controlSize(.small)
            }
        } header: {
            Text(L("Confirm"))
        } footer: {
            Text(L("The one-time code is sent only to this server. Pair only with a server you trust."))
                .foregroundStyle(.secondary)
        }
    }

    private var confirmTitle: String {
        guard let host = form.payload?.serverHost else { return L("Pair") }
        return L("Pair with \(host)")
    }

    private func redeem() async {
        guard let payload = form.payload, !isRedeeming else { return }
        isRedeeming = true
        failure = nil
        defer { isRedeeming = false }
        switch await settings.pair(with: payload) {
        case let .success(config):
            onPaired(config)
            dismiss()
        case let .failure(error):
            failure = error.localizedDescription
        }
    }
}
