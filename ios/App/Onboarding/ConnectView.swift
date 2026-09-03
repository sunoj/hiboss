// First-run connection screen: server URL + Boss Token, verified on connect.
// Exports: ConnectView that populates the ConnectionStore on success.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import SwiftUI

struct ConnectView: View {
    @ObservedObject var connection: ConnectionStore
    @State private var connecting = false
    @State private var error: String?
    @State private var showingScanner = false
    @FocusState private var focus: Field?

    enum Field { case server, token }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            logo
            Text("Connect to HiBoss")
                .font(.hbH2)
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
            Text("Use a pairing code from your Mac, or enter a server URL and Boss Token.")
                .font(.hbSmall)
                .foregroundStyle(Theme.ink2)
                .padding(.top, 4)

            field(title: String(localized: "SERVER URL"), text: $connection.serverAddress,
                  placeholder: "https://hiboss.you.workers.dev", field: .server, secure: false)
                .padding(.top, 26)
            field(title: String(localized: "BOSS TOKEN"), text: $connection.bossToken,
                  placeholder: "hb_…", field: .token, secure: true)
                .padding(.top, 14)

            scanButton.padding(.top, 16)

            if let error {
                Text(error)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.negative)
                    .padding(.top, 12)
            }

            connectButton.padding(.top, 22)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showingScanner) {
            PairingScannerView { payload in
                showingScanner = false
                pair(payload)
            }
        }
    }

    private var logo: some View {
        Text("h")
            .font(.title2.monospaced().weight(.semibold))
            .foregroundStyle(Color(uiColor: UIColor(rgb: 0xECEBE7)))
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [Color(uiColor: UIColor(rgb: 0x3A3A36)), Color(uiColor: UIColor(rgb: 0x171715))],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func field(
        title: String, text: Binding<String>, placeholder: String,
        field: Field, secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).hbLabel().foregroundStyle(Theme.ink4)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }
            .font(.hbBody)
            .focused($focus, equals: field)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focus == field ? Theme.ink3 : Theme.line2, lineWidth: 1)
            )
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: 8) {
                if connecting { ProgressView().tint(.white) }
                Text(connecting ? String(localized: "Connecting…") : String(localized: "Connect"))
                    .font(.hbBodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(connecting)
    }

    private var scanButton: some View {
        Button {
            focus = nil
            error = nil
            showingScanner = true
        } label: {
            Label("Scan a code", systemImage: "qrcode.viewfinder")
                .font(.hbBodyStrong)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.line2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(connecting)
    }

    private func connect() {
        focus = nil
        error = nil
        connecting = true
        Task {
            let result = await connection.connect()
            connecting = false
            if case let .failure(failure) = result {
                error = failure.localizedDescription
            }
        }
    }

    private func pair(_ payload: PairingPayload) {
        focus = nil
        error = nil
        connecting = true
        Task {
            let result = await connection.pair(payload: payload, deviceLabel: DeviceLabel.current())
            connecting = false
            if case let .failure(failure) = result {
                error = failure.localizedDescription
            }
        }
    }
}
