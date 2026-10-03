// Native device-pairing sheet with an in-memory QR code, copyable link, and expiry countdown.
// Exports: DevicePairingSheet.
// Dependencies: SwiftUI, AppKit pasteboard, AppSettings, and HibossKit's DevicePairingModel.

import AppKit
import HibossKit
import SwiftUI

struct DevicePairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: DevicePairingModel

    init(settings: AppSettings) {
        _model = StateObject(wrappedValue: DevicePairingModel(config: try? settings.connectionConfig().get()))
    }

    var body: some View {
        Form {
            Section {
                Text(L("Scan this QR code with your phone to enroll it in HiBoss. The code is valid for five minutes and can be used once."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(L("Pair a new device"))
            }

            Section {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    pairingContent(at: context.date)
                }
            } header: {
                Text(L("Pairing code"))
            }

            Section {
                requestButton
                if let message = model.failureMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text(L("On a Mac, paste the link into Pair with Code. The link carries the server and a one-time code, never a token."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 430, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
        .task { await model.requestCode() }
        .task(id: model.grant?.code) { await model.monitorRedemption() }
    }

    @ViewBuilder
    private func pairingContent(at now: Date) -> some View {
        switch model.state(at: now) {
        case let .paired(deviceLabel):
            pairedContent(deviceLabel: deviceLabel)
        case let .ready(grant, link):
            if let image = model.qrImage {
                readyContent(grant: grant, link: link, image: image, now: now)
            }
        case .requesting:
            ProgressView(L("Requesting a pairing code…"))
                .frame(maxWidth: .infinity, minHeight: 300)
        case let state:
            unavailableContent(for: state)
        }
    }

    private func pairedContent(deviceLabel: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(DesignTokens.live)
            Text(L("Device connected"))
                .font(.title2.weight(.semibold))
            Text(deviceLabel)
                .font(.body.weight(.medium))
            Text(L("This one-time code has been used."))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pairing-success")
    }

    private func readyContent(grant: PairingGrant, link: PairingLink, image: CGImage, now: Date) -> some View {
        VStack(spacing: 12) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 260, height: 260)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(L("Device pairing QR code"))

            LabeledContent(L("Valid for")) {
                Text(PairingValidity.formatted(
                    remainingSeconds: PairingValidity.remainingSeconds(expiresAt: grant.expiresAt, now: now)
                ))
                .monospacedDigit()
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            } label: {
                Label(L("Copy Link"), systemImage: "doc.on.doc")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func unavailableContent(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .frame(maxWidth: .infinity, minHeight: 300)
    }

    @ViewBuilder
    private func unavailableContent(for state: PairingContentState) -> some View {
        switch state {
        case .notConfigured:
            unavailableContent(
                title: L("Pairing is not configured"), systemImage: "network.slash",
                description: L("Configure the server URL and Boss Token before pairing a device.")
            )
        case .noCode:
            unavailableContent(
                title: L("No pairing code"), systemImage: "qrcode",
                description: L("A pairing code is not available yet.")
            )
        case .expired:
            unavailableContent(
                title: L("Pairing code expired"), systemImage: "clock.badge.exclamationmark",
                description: L("Request a fresh code before scanning.")
            )
        case .permissionDenied, .requestFailed:
            let failure: PairingRequestFailure = state == .permissionDenied ? .permissionDenied : .failed
            unavailableContent(
                title: failure.title,
                systemImage: state == .permissionDenied ? "person.badge.key" : "exclamationmark.triangle",
                description: failure.detail
            )
        case .invalidLink:
            unavailableContent(
                title: L("Pairing link unavailable"), systemImage: "link.badge.plus",
                description: L("Pairing links need an HTTPS server URL. Plain HTTP works only for localhost.")
            )
        case .qrUnavailable:
            unavailableContent(
                title: L("QR code unavailable"), systemImage: "qrcode",
                description: L("HiBoss could not render the pairing QR code.")
            )
        case .requesting, .paired, .ready:
            EmptyView()
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        switch model.state(at: Date()) {
        case .paired:
            Button { Task { await model.requestCode() } } label: {
                Label(L("Pair another device"), systemImage: "qrcode")
            }
            .disabled(model.isRequesting)
        case .expired:
            Button { Task { await model.requestCode() } } label: {
                Label(L("Request a fresh code"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isRequesting)
        case .requestFailed:
            Button { Task { await model.requestCode() } } label: {
                Label(L("Try again"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isRequesting)
        default:
            EmptyView()
        }
    }
}
