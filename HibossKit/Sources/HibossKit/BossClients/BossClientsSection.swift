// Native device rows with inventory state and confirmed revocation.
// Exports: BossClientsSection, embedded in macOS and iOS Settings forms.
// Dependencies: SwiftUI, BossClientsStore, and localized HibossKit strings.

import SwiftUI

public struct BossClientsSection: View {
    @StateObject private var store: BossClientsStore
    @State private var pendingRevocation: BossClient?
    @State private var showsConfirmation = false

    public init(api: any BossClientsServing) {
        _store = StateObject(wrappedValue: BossClientsStore(api: api))
    }

    public var body: some View {
        Section {
            if store.isBusy {
                ProgressView(kitL("Loading devices…"))
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if !store.isBusy && store.clients.isEmpty {
                Text(kitL("No devices registered.")).foregroundStyle(.secondary)
            }
            ForEach(store.clients) { client in
                row(client)
            }
            Button(kitL("Refresh devices")) { Task { await store.load() } }
                .disabled(store.isBusy)
        } header: {
            Text(kitL("Devices"))
        }
        .task { await store.load() }
        .alert(kitL("Revoke device?"), isPresented: $showsConfirmation, presenting: pendingRevocation) { client in
            Button(kitL("Cancel"), role: .cancel) { pendingRevocation = nil }
            Button(kitL("Revoke"), role: .destructive) {
                Task { await store.revoke(client) }
                pendingRevocation = nil
            }
        } message: { client in
            Text(client.label) + Text("\n") + Text(kitL("This device will lose access and stop receiving push notifications."))
        }
    }

    private func row(_ client: BossClient) -> some View {
        HStack(alignment: .top) {
            Image(systemName: client.kind.symbol)
                .foregroundStyle(.secondary)
                .accessibilityLabel(client.kind.rawValue)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.label).font(.headline)
                if let date = client.lastSeenDate {
                    (Text(kitL("Last seen")) + Text(" ") + Text(date, style: .relative))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(kitL("Last seen: never")).font(.caption).foregroundStyle(.secondary)
                }
                badges(client)
            }
            Spacer()
            if client.canRevoke {
                Button(kitL("Revoke"), role: .destructive) {
                    pendingRevocation = client
                    showsConfirmation = true
                }
                .buttonStyle(.borderless)
                .disabled(store.isBusy)
                .accessibilityLabel(Text(kitL("Revoke")) + Text(" ") + Text(client.label))
            }
        }
    }

    private func badges(_ client: BossClient) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { badgeLabels(client) }
            VStack(alignment: .leading) { badgeLabels(client) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func badgeLabels(_ client: BossClient) -> some View {
        if client.isCurrent { Label(kitL("This device"), systemImage: "checkmark.circle") }
        if client.revokedAt != nil { Label(kitL("Revoked"), systemImage: "nosign") }
        if client.hasPushDevice { Label(kitL("Push"), systemImage: "bell") }
        if client.hasSigningKey { Label(kitL("Signing key"), systemImage: "key") }
    }
}
