// Settings screen that issues a one-time pairing code and shows its QR plus copyable link.
// Exports: PairDeviceView.
// Dependencies: SwiftUI, UIKit pasteboard, HibossKit's DevicePairingModel, and CopyFeedback.

import HibossKit
import SwiftUI
import UIKit

struct PairDeviceView: View {
    @StateObject private var model: DevicePairingModel
    @State private var copyFeedback = CopyFeedback()
    @Environment(\.dismiss) private var dismiss

    init(config: ConnectionConfig?) {
        _model = StateObject(wrappedValue: isDemoMode
            ? DevicePairingModel(serverURL: DemoDevices.serverURL, issuer: DemoPairingIssuer())
            : DevicePairingModel(config: config))
    }

    var body: some View {
        // One clock drives the code, its countdown and the action below it: expiry changes
        // no published state, so anything outside the timeline would keep its stale state.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let state = model.state(at: context.date)
            Form {
                Section {
                    content(state, now: context.date)
                } footer: {
                    if case .ready = state {
                        Text("Scan on the other iPhone, or paste the link into Pair with Code on a Mac.")
                        Text("This code works once and expires in five minutes.")
                        Text("This phone stays signed in.")
                    }
                }
                if let message = model.failureMessage {
                    Section { Text(verbatim: message).foregroundStyle(Theme.ink2) }
                }
                actionSection(state)
            }
        }
        .navigationTitle("Pair another device")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.requestCode() }
        .task(id: model.grant?.code) { await model.monitorRedemption() }
        .sensoryFeedback(.success, trigger: copyFeedback.count)
        .task(id: copyFeedback.count) {
            let copy = copyFeedback.count
            guard copy > 0, (try? await Task.sleep(for: CopyFeedback.duration)) != nil else { return }
            copyFeedback.expire(copy: copy)
        }
    }

    @ViewBuilder
    private func content(_ state: PairingContentState, now: Date) -> some View {
        switch state {
        case let .ready(grant, link):
            readyContent(grant: grant, link: link, now: now)
        case let .paired(deviceLabel):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.positive)
                Text("Device connected").font(.headline)
                Text(verbatim: deviceLabel).foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pairing-success")
        case .requesting:
            SettingsWaitView(title: "Requesting a pairing code…") { dismiss() }
                .frame(maxWidth: .infinity, minHeight: 240)
        case .permissionDenied:
            failureContent(.permissionDenied, systemImage: "person.badge.key")
        case .requestFailed:
            failureContent(.failed, systemImage: "exclamationmark.triangle")
        case .expired:
            ContentUnavailableView("Pairing code expired", systemImage: "clock.badge.exclamationmark",
                                   description: Text("Request a fresh code before scanning."))
        case .notConfigured, .noCode:
            ContentUnavailableView("No pairing code", systemImage: "qrcode",
                                   description: Text("Connect to a server before pairing another device."))
        case .invalidLink, .qrUnavailable:
            ContentUnavailableView("Pairing link unavailable", systemImage: "link.badge.plus",
                                   description: Text("Pairing links need an HTTPS server URL.")
                                    + Text(" Plain HTTP works only for localhost."))
        }
    }

    private func readyContent(grant: PairingGrant, link: PairingLink, now: Date) -> some View {
        VStack(spacing: 14) {
            if let image = model.qrImage {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260)
                    .accessibilityLabel("Device pairing QR code")
            }
            LabeledContent("Valid for") {
                Text(verbatim: PairingValidity.formatted(
                    remainingSeconds: PairingValidity.remainingSeconds(expiresAt: grant.expiresAt, now: now)
                ))
                .monospacedDigit()
            }
            Text("Waiting for the other device to connect.").foregroundStyle(Theme.ink2)
            linkControls(link)
        }
        .padding(.vertical, 8)
    }

    private func linkControls(_ link: PairingLink) -> some View {
        VStack(spacing: 14) {
            Text(verbatim: link.url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.ink2)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button { copy(link) } label: {
                Group {
                    if copyFeedback.isShowing {
                        Label("Copied", systemImage: "checkmark")
                    } else {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Copies the link, then confirms it on screen, by haptic, and to VoiceOver.
    private func copy(_ link: PairingLink) {
        UIPasteboard.general.string = link.url.absoluteString
        copyFeedback.copied()
        AccessibilityNotification.Announcement(String(localized: "Link copied")).post()
    }

    private func failureContent(_ failure: PairingRequestFailure, systemImage: String) -> some View {
        ContentUnavailableView {
            Label { Text(verbatim: failure.title) } icon: { Image(systemName: systemImage) }
        } description: {
            Text(verbatim: failure.detail)
        }
    }

    @ViewBuilder
    private func actionSection(_ state: PairingContentState) -> some View {
        switch state {
        case .paired:
            retryButton { Label("Pair another device", systemImage: "qrcode") }
        case .expired:
            retryButton { Label("Request a fresh code", systemImage: "arrow.clockwise") }
        case .requestFailed:
            retryButton { Label("Try again", systemImage: "arrow.clockwise") }
        default:
            EmptyView()
        }
    }

    private func retryButton(@ViewBuilder label: () -> some View) -> some View {
        Section {
            Button(action: { Task { await model.requestCode() } }, label: label)
                .disabled(model.isRequesting)
        }
    }
}
