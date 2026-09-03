// Native device-pairing sheet with an in-memory QR code and expiry countdown.
// Exports: PairingLink, PairingValidity, PairingQRCodeGenerator, and DevicePairingSheet.
// Dependencies: SwiftUI, AppKit/CoreImage, AppSettings, and HibossKit pairing contracts.

import AppKit
import CoreImage
import HibossKit
import SwiftUI

enum PairingLinkError: Error, Equatable {
    case invalidCode
    case invalidServerURL
}

struct PairingLink: Equatable, Sendable {
    let url: URL

    init(serverURL: URL, code: String) throws {
        guard PairingGrant.isValidCode(code) else { throw PairingLinkError.invalidCode }
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        )
        guard let encodedServer = serverURL.absoluteString.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ), let url = URL(string: "hiboss://pair?server=\(encodedServer)&code=\(code)") else {
            throw PairingLinkError.invalidServerURL
        }
        self.url = url
    }
}

enum PairingValidity {
    static func isValid(expiresAt: Date, now: Date) -> Bool {
        expiresAt > now
    }

    static func remainingSeconds(expiresAt: Date, now: Date) -> Int {
        max(0, Int(ceil(expiresAt.timeIntervalSince(now))))
    }

    static func formatted(remainingSeconds: Int) -> String {
        let minutes = max(0, remainingSeconds) / 60
        let seconds = max(0, remainingSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum PairingQRCodeGenerator {
    static func image(for link: PairingLink) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(link.url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
            return nil
        }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

struct DevicePairingSheet: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var grant: PairingGrant?
    @State private var isRequesting = false
    @State private var requestFailure: PairingRequestFailure?
    @State private var errorMessage: String?

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

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text(L("The phone will receive the server address and one-time code from this QR code."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 430, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Done")) { dismiss() }
            }
        }
        .task { await requestPairingCode() }
    }

    @ViewBuilder
    private func pairingContent(at now: Date) -> some View {
        let state = contentState(at: now)
        switch state {
        case let .ready(grant, link):
            if let image = PairingQRCodeGenerator.image(for: link) {
                readyPairingContent(grant: grant, image: image, now: now)
            } else {
                unavailableContent(for: .qrUnavailable)
            }
        case .requesting:
            ProgressView(L("Requesting a pairing code…"))
                .frame(maxWidth: .infinity, minHeight: 300)
        default:
            unavailableContent(for: state)
        }
    }

    private func readyPairingContent(grant: PairingGrant, image: NSImage, now: Date) -> some View {
        VStack(spacing: 12) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(L("Device pairing QR code"))

            LabeledContent(L("Valid for")) {
                Text(PairingValidity.formatted(
                    remainingSeconds: PairingValidity.remainingSeconds(
                        expiresAt: grant.expiresAt, now: now
                    )
                ))
                .monospacedDigit()
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
        case .permissionDenied:
            unavailableContent(
                title: L("Administrator permission required"), systemImage: "person.badge.key",
                description: L("Only an administrator can mint pairing codes. Use an admin Boss Token.")
            )
        case .requestFailed:
            unavailableContent(
                title: L("Couldn’t request a pairing code"), systemImage: "exclamationmark.triangle",
                description: L("Try again when the server is reachable.")
            )
        case .invalidLink:
            unavailableContent(
                title: L("Pairing link unavailable"), systemImage: "link.badge.plus",
                description: L("The server URL or pairing code could not be encoded.")
            )
        case .qrUnavailable:
            unavailableContent(
                title: L("QR code unavailable"), systemImage: "qrcode",
                description: L("HiBoss could not render the pairing QR code.")
            )
        case .requesting, .ready:
            EmptyView()
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        switch currentContentState {
        case .expired:
            Button { Task { await requestPairingCode() } } label: {
                Label(L("Request a fresh code"), systemImage: "arrow.clockwise")
            }
            .disabled(isRequesting)
        case .requestFailed:
            Button { Task { await requestPairingCode() } } label: {
                Label(L("Try again"), systemImage: "arrow.clockwise")
            }
            .disabled(isRequesting)
        default:
            EmptyView()
        }
    }

    private var currentContentState: PairingContentState { contentState(at: Date()) }

    private func contentState(at now: Date) -> PairingContentState {
        let linkResult = pairingLinkResult
        let canRenderQRCode: Bool
        if case let .success(link) = linkResult {
            canRenderQRCode = PairingQRCodeGenerator.image(for: link) != nil
        } else {
            canRenderQRCode = false
        }
        return PairingContentState.derive(
            grant: grant,
            hasConfiguredServer: configuredServerURL != nil,
            now: now,
            isRequesting: isRequesting,
            requestFailure: requestFailure,
            linkResult: linkResult,
            canRenderQRCode: canRenderQRCode
        )
    }

    private var pairingLinkResult: Result<PairingLink, PairingLinkError>? {
        guard let grant, let serverURL = configuredServerURL else { return nil }
        do {
            return .success(try PairingLink(serverURL: serverURL, code: grant.code))
        } catch let error as PairingLinkError {
            return .failure(error)
        } catch {
            return .failure(.invalidServerURL)
        }
    }

    private var configuredServerURL: URL? {
        guard case let .success(config) = settings.connectionConfig() else { return nil }
        return config.serverURL
    }

    private func requestPairingCode() async {
        guard !isRequesting else { return }
        guard case let .success(config) = settings.connectionConfig() else {
            grant = nil
            requestFailure = nil
            errorMessage = L("Configure the server URL and Boss Token before pairing a device.")
            return
        }
        isRequesting = true
        grant = nil
        requestFailure = nil
        errorMessage = nil
        defer { isRequesting = false }
        do {
            grant = try await HibossAPI(config: config).requestPairingCode()
        } catch {
            let failure = PairingRequestFailure.from(error)
            requestFailure = failure
            errorMessage = failure == .permissionDenied ? nil : error.localizedDescription
        }
    }
}
