// Sheet for a pairing code typed by hand, or prefilled from a tapped `hiboss://pair` link.
// Exports: PairingCodeEntryView, validating through PairingPayload before it hands off.
// Dependencies: SwiftUI, HibossKit PairingPayload, theme tokens.

import HibossKit
import SwiftUI

struct PairingCodeEntryView: View {
    let onPair: (PairingPayload) -> Void
    @State private var server: String
    @State private var code: String
    @State private var error: String?
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    enum Field { case server, code }

    init(prefill: PairingPayload? = nil, onPair: @escaping (PairingPayload) -> Void) {
        self.onPair = onPair
        _server = State(initialValue: prefill?.serverURL.absoluteString ?? "")
        _code = State(initialValue: prefill?.code ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $server,
                              prompt: Text(verbatim: "https://hiboss.you.workers.dev"))
                        .keyboardType(.URL)
                        .focused($focus, equals: .server)
                        .accessibilityIdentifier("pairing-server-field")
                    TextField("Pairing code", text: $code, prompt: Text(verbatim: "hb_pair_…"))
                        .font(.hbMono)
                        .focused($focus, equals: .code)
                        .accessibilityIdentifier("pairing-code-field")
                } footer: {
                    Text(verbatim: error ?? String(localized:
                        "On a device that is already signed in, choose Pair another device. Enter the server and the one-time code it shows."
                    ))
                    .foregroundStyle(error == nil ? Theme.ink2 : Theme.negative)
                    .accessibilityIdentifier("pairing-code-footer")
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(submit)
            .navigationTitle("Enter pairing code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair", action: submit)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("pairing-code-submit")
                }
            }
            .onAppear { if server.isEmpty { focus = .server } }
        }
    }

    /// A pasted `hiboss://pair` link carries both values; otherwise the two fields do.
    private func submit() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = trimmed.lowercased().hasPrefix("hiboss://")
            ? PairingPayload.parse(trimmed)
            : PairingPayload.make(server: server, code: trimmed)
        switch result {
        case let .success(payload):
            focus = nil
            onPair(payload)
        case let .failure(failure):
            error = ServerAddressPolicy.message(for: failure)
        }
    }
}
