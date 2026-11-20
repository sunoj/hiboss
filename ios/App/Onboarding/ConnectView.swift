// First-run connection screen: pairing (scan, typed code or link), Boss Token, or the demo.
// Exports: ConnectView that populates the ConnectionStore on success.
// Dependencies: SwiftUI, HibossKit, theme tokens.

import HibossKit
import SwiftUI

struct ConnectView: View {
    @ObservedObject var connection: ConnectionStore
    @State private var connecting = false
    @State private var error: String?
    @State private var showingScanner = false
    @State private var pairing = false
    @State private var showingCodeEntry = false
    @State private var codePrefill: PairingPayload?
    @ObservedObject private var links = PairingLinkInbox.shared
    @FocusState private var focus: Field?
    @Environment(\.openURL) private var openURL

    enum Field { case server, token, deviceLabel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                logo
                Text("Connect to HiBoss")
                    .font(.hbH2)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, Space.xl)
                Text("Use a pairing code from your Mac, or enter a server URL and Boss Token.")
                    .font(.hbSmall)
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, Space.xxs)

                credentialFields

                scanButton.padding(.top, Space.m)
                enterCodeButton.padding(.top, Space.s)

                if let error {
                    Text(verbatim: error)
                        .font(.hbCaption)
                        .foregroundStyle(Theme.negative)
                        .accessibilityIdentifier("connect-error")
                        .padding(.top, Space.s)
                }

                connectButton.padding(.top, Space.xl)
                if connecting {
                    PendingStateView(
                        title: pendingTitle,
                        detail: String(localized:
            "Still waiting for the server. Your credentials are kept here. Check your connection."
                        ),
                        onSettings: openNetworkSettings
                    ).padding(.top, Space.s)
                }
                ConnectAlternatives(onExploreDemo: DemoSession.shared.enter)
                    .disabled(connecting)
                    .padding(.top, Space.l)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showingScanner) {
            PairingScannerView { payload in
                showingScanner = false
                pair(payload)
            }
        }
        .sheet(isPresented: $showingCodeEntry) {
            PairingCodeEntryView(prefill: codePrefill) { payload in
                showingCodeEntry = false
                pair(payload)
            }
        }
        .onAppear {
            pairDemoPayloadIfPresent()
            openPendingLink()
        }
        .onChange(of: links.pending) { _, _ in openPendingLink() }
        .onChange(of: links.refusal) { _, _ in openPendingLink() }
    }

    private var logo: some View {
        HiBossBrandIcon(size: 52)
    }

    private var credentialFields: some View {
        VStack(spacing: Space.m) {
            field(title: String(localized: "SERVER URL"), text: $connection.serverAddress,
                  placeholder: "https://hiboss.you.workers.dev", field: .server, secure: false)
            field(title: String(localized: "BOSS TOKEN"), text: $connection.bossToken,
                  placeholder: "hb_…", field: .token, secure: true)
            field(title: String(localized: "Device label"), text: $connection.deviceLabel,
                  placeholder: UIDevice.current.name, field: .deviceLabel, secure: false)
        }
        .padding(.top, Space.xl)
    }

    private func field(
        title: String, text: Binding<String>, placeholder: String,
        field: Field, secure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: title).hbLabel().foregroundStyle(Theme.ink4)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .keyboardType(field == .server ? .URL : .default)
                        .autocorrectionDisabled()
                }
            }
            .font(.hbBody)
            .focused($focus, equals: field)
            .accessibilityIdentifier(fieldIdentifier(field))
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(minHeight: ControlMetric.fullWidth)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(focus == field ? Theme.ink3 : Theme.line2, lineWidth: 1)
            )
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: Space.xs) {
                if connecting { DelayedProgressView(tint: Theme.onAccent) }
                Text(verbatim: connecting ? pendingTitle : String(localized: "Connect"))
                    .font(.hbBodyStrong)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: ControlMetric.fullWidth)
        }
        .prominentAction()
        .disabled(connecting)
    }

    private func fieldIdentifier(_ field: Field) -> String {
        switch field {
        case .server: "server-url-field"
        case .token: "boss-token-field"
        case .deviceLabel: "device-label-field"
        }
    }

    private var scanButton: some View {
        secondaryButton {
            showingScanner = true
        } label: {
            Label("Scan a code", systemImage: "qrcode.viewfinder")
        }
    }

    private var enterCodeButton: some View {
        secondaryButton {
            codePrefill = nil
            showingCodeEntry = true
        } label: {
            Label("Enter pairing code", systemImage: "keyboard")
        }
        .accessibilityIdentifier("connect-enter-code")
    }

    private func secondaryButton(
        action: @escaping () -> Void, @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            focus = nil
            error = nil
            action()
        } label: {
            label()
                .font(.hbBodyStrong)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(connecting)
    }

    private func connect() {
        focus = nil
        error = nil
        connecting = true
        pairing = false
        Task {
            try? await DemoDelay.wait("CONNECT")
            // A demo never contacts a server; the onboarding preview stops at the wait.
            guard !isDemoMode else { connecting = false; return }
            let result = await connection.connect()
            connecting = false
            if case let .failure(failure) = result {
                error = ServerAddressPolicy.describe(failure)
            }
        }
    }

    private func pair(_ payload: PairingPayload) {
        focus = nil
        error = nil
        connection.serverAddress = payload.serverURL.absoluteString
        connecting = true
        pairing = true
        Task {
            try? await DemoDelay.wait("CONNECT")
            guard !isDemoMode else { connecting = false; return }
            let result = await connection.pair(payload: payload, deviceLabel: DeviceLabel.current())
            connecting = false
            if case let .failure(failure) = result {
                error = ServerAddressPolicy.describe(failure)
            }
        }
    }

    private var pendingTitle: String {
        pairing ? String(localized: "Pairing this iPhone…") : String(localized: "Connecting…")
    }

    private func openNetworkSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    /// A tapped `hiboss://pair` link opens the code sheet prefilled; the boss confirms with Pair.
    private func openPendingLink() {
        guard !connecting else { return }
        if let refusal = links.takeRefusal() { error = refusal }
        guard let payload = links.take() else { return }
        focus = nil
        error = nil
        showingScanner = false
        codePrefill = payload
        showingCodeEntry = true
    }

    private func pairDemoPayloadIfPresent() {
        guard isDemoMode, let rawValue = ProcessInfo.processInfo.environment["HIBOSS_DEMO_PAIRING_SCAN"],
              case let .success(payload) = PairingPayload.parse(rawValue) else { return }
        pair(payload)
    }
}
