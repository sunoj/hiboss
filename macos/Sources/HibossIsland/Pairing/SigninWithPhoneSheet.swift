// Native sheet for "Sign in with iPhone": server, QR code with countdown, then the 6-digit code.
// Exports: SigninWithPhoneSheet.
// Dependencies: SwiftUI, AppSettings.adopt(_:server:), and SigninWithPhoneModel.

import HibossKit
import SwiftUI

struct SigninWithPhoneSheet: View {
    let onSignedIn: (ConnectionConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SigninWithPhoneModel
    @FocusState private var isCodeFocused: Bool

    init(settings: AppSettings, onSignedIn: @escaping (ConnectionConfig) -> Void) {
        self.init(model: SigninWithPhoneModel(
            serverAddress: settings.serverAddress,
            deviceLabel: settings.outgoingDeviceLabel,
            persist: { grant, server in try settings.adopt(grant, server: server) }
        ), onSignedIn: onSignedIn)
    }

    init(model: @autoclosure @escaping () -> SigninWithPhoneModel, onSignedIn: @escaping (ConnectionConfig) -> Void) {
        self.onSignedIn = onSignedIn
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        Form {
            switch model.phase {
            case .editingServer, .opening:
                serverSection
            case .awaitingApproval:
                scanSection
            case .enteringCode, .completing:
                codeSection
            case let .ended(ending):
                endedSection(ending)
            case .signedIn:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 430, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) { confirmButton }
        }
        .onDisappear { model.cancel() }
        .onChange(of: model.phase) { _, phase in
            if phase == .enteringCode { isCodeFocused = true }
            guard case let .signedIn(config) = phase else { return }
            onSignedIn(config)
            dismiss()
        }
    }

    private var serverSection: some View {
        Section {
            Text(L("This Mac shows a QR code. Scan it with HiBoss on a signed-in iPhone to approve this Mac."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("Server URL"), text: $model.serverAddress)
                .font(.system(.body, design: .monospaced))
                .onSubmit { Task { await model.start() } }
            noticeLabel
            if model.phase == .opening {
                ProgressView(L("Opening a sign-in request…")).controlSize(.small)
            }
        } header: {
            Text(L("Sign in with iPhone"))
        } footer: {
            Text(L("Use the server your iPhone is signed in to. Only an admin or manager can approve."))
                .foregroundStyle(.secondary)
        }
        .disabled(model.phase == .opening)
    }

    private var scanSection: some View {
        Section {
            Text(L("Scan with HiBoss on your iPhone, then type the code it shows."))
                .fixedSize(horizontal: false, vertical: true)
            if let image = model.qrImage {
                Image(image, scale: 1, label: Text(L("Sign-in QR code")))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(16)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity)
            }
            requestDetails
            Label {
                Text(L("Waiting for approval on your iPhone…"))
            } icon: {
                ProgressView().controlSize(.small)
            }
            .foregroundStyle(.secondary)
        } header: {
            Text(L("Sign in with iPhone"))
        }
    }

    private var codeSection: some View {
        Section {
            LabeledContent(L("6-digit code")) {
                TextField(L("6-digit code"), text: $model.code, prompt: Text(verbatim: "000000"))
                    .labelsHidden()
                    .textContentType(.oneTimeCode)
                    .font(.system(.title2, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($isCodeFocused)
                    .onSubmit { Task { await model.submitCode() } }
                    .accessibilityHint(L("Type the code shown on your iPhone."))
            }
            noticeLabel
            if model.phase == .completing {
                ProgressView(L("Signing in…")).controlSize(.small)
            }
            requestDetails
        } header: {
            Text(L("Approved on your iPhone"))
        } footer: {
            Text(L("Type the 6-digit code your iPhone shows. It works only for this request."))
                .foregroundStyle(.secondary)
        }
        .disabled(model.phase == .completing)
    }

    @ViewBuilder
    private var requestDetails: some View {
        LabeledContent(L("Server")) {
            Text(verbatim: model.serverHost ?? "—")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        if let expiresAt = model.expiresAt {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                LabeledContent(L("Valid for")) {
                    Text(PairingValidity.formatted(
                        remainingSeconds: PairingValidity.remainingSeconds(expiresAt: expiresAt, now: context.date)
                    ))
                    .monospacedDigit()
                }
            }
        }
    }

    private func endedSection(_ ending: SigninWithPhoneModel.Ending) -> some View {
        let copy = SigninPhoneCopy.ending(ending)
        return Section {
            ContentUnavailableView {
                Label(copy.title, systemImage: copy.systemImage)
            } description: {
                Text(copy.detail)
            } actions: {
                Button(L("Start Over")) { Task { await model.startOver() } }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    @ViewBuilder
    private var noticeLabel: some View {
        if let notice = model.notice {
            Label(SigninPhoneCopy.notice(notice), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        switch model.phase {
        case .editingServer, .opening:
            Button(L("Continue")) { Task { await model.start() } }
                .disabled(!model.canStart)
        case .enteringCode, .completing:
            Button(L("Sign In")) { Task { await model.submitCode() } }
                .disabled(!model.canSubmitCode)
        case .awaitingApproval, .ended, .signedIn:
            EmptyView()
        }
    }
}

/// User-facing copy for the sign-in model's notices and endings.
enum SigninPhoneCopy {
    static func notice(_ notice: SigninWithPhoneModel.Notice) -> String {
        switch notice {
        case let .invalidServer(error): error.localizedDescription
        case .codeMismatch: L("That code didn't match. Check the code on your iPhone and try again.")
        case .tooManyRequests: L("The server is busy with sign-in requests. Try again in a few minutes.")
        case .requestFailed: L("Couldn't reach the server. Check the address and your connection, then try again.")
        }
    }

    static func ending(_ ending: SigninWithPhoneModel.Ending) -> (title: String, systemImage: String, detail: String) {
        switch ending {
        case .rejected:
            (L("Sign-in declined"), "hand.raised",
             L("The request was declined on the iPhone, or too many wrong codes were entered."))
        case .expired:
            (L("Sign-in request expired"), "clock.badge.exclamationmark",
             L("A request lasts ten minutes. Start over for a new QR code."))
        case .usedElsewhere:
            (L("Request already used"), "person.crop.circle.badge.xmark",
             L("This request was completed somewhere else. Start over to sign in this Mac."))
        case .failed:
            (L("Couldn't finish signing in"), "exclamationmark.triangle",
             L("HiBoss couldn't save the sign-in on this Mac. Start over to try again."))
        }
    }
}
