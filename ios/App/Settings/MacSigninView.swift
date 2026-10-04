// Settings > Sign in a Mac: scan the Mac's QR code, review the request, approve or reject it.
// Exports: MacSigninView. The approval code itself is drawn by MacSigninCodeView.
// Dependencies: SwiftUI, HibossKit, MacSigninModel, PairingScannerView, Theme tokens.

import HibossKit
import SwiftUI

struct MacSigninView: View {
    @StateObject private var model: MacSigninModel
    @State private var scanning = false
    @State private var confirmsReject = false
    @Environment(\.dismiss) private var dismiss

    init(config: ConnectionConfig?, api: HibossAPI?) {
        _model = StateObject(wrappedValue: isDemoMode
            ? MacSigninModel(serverURL: DemoDevices.serverURL, api: DemoSigninAPI())
            : MacSigninModel(serverURL: config?.serverURL, api: api))
    }

    var body: some View {
        content
            .navigationTitle("Sign in a Mac")
            .navigationBarTitleDisplayMode(.inline)
            // Leaving would drop the code for good, so the approved screen ends only through Done.
            .navigationBarBackButtonHidden(isShowingCode)
            .sheet(isPresented: $scanning) {
                PairingScannerView(
                    title: String(localized: "Scan sign-in code"),
                    cameraPurpose: String(localized: "Camera access is needed to scan the code on your Mac.")
                ) { rawValue in
                    let outcome = model.accept(scanned: rawValue)
                    if outcome == .accepted { scanning = false }
                    return outcome
                }
            }
            .task(id: model.link?.requestID) { await model.load() }
            .onAppear(perform: scanDemoLinkIfPresent)
    }

    private var isShowingCode: Bool {
        if case .approved = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            intro
        case .loading:
            ProgressView("Loading request…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .review(summary):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                review(summary, now: context.date)
            }
        case let .approved(code):
            MacSigninCodeView(code: code) { dismiss() }
        case let .rejected(deviceLabel):
            outcome(Text("\(deviceLabel) was not signed in"), systemImage: "xmark.circle")
        case let .failed(failure):
            outcome(Text(verbatim: failure.message), systemImage: "exclamationmark.triangle")
        }
    }

    private var intro: some View {
        Form {
            Section {
                Label("On your Mac, choose Sign in with iPhone in HiBoss, then scan the code it shows.",
                      systemImage: "laptopcomputer.and.iphone")
                Button { scanning = true } label: {
                    Label("Scan Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("mac-signin.scan")
            } footer: {
                if let rejection = model.scanRejection {
                    Label { Text(verbatim: rejection) } icon: { Image(systemName: "xmark.octagon") }
                        .foregroundStyle(Theme.negative)
                        .accessibilityIdentifier("mac-signin.scan-rejection")
                }
            }
        }
    }

    private func review(_ summary: SigninRequestSummary, now: Date) -> some View {
        let status = MacSigninModel.status(of: summary, at: now)
        return Form {
            Section {
                // Chosen by the requesting Mac, so it is shown as its claim, not as a fact.
                LabeledContent("Calls itself") { Text(verbatim: summary.deviceLabel) }
                if let origin = summary.origin, !origin.isEmpty {
                    LabeledContent("Location") { Text(verbatim: origin) }
                }
                if status == .pending, let expiry = ISODate.parse(summary.expiresAt) {
                    LabeledContent("Expires in") {
                        Text(verbatim: PairingValidity.formatted(
                            remainingSeconds: PairingValidity.remainingSeconds(expiresAt: expiry, now: now)
                        ))
                        .monospacedDigit()
                    }
                }
            } header: {
                Text("Mac")
            } footer: {
                if status == .pending {
                    Text("Approve only if you just chose Sign in with iPhone on this Mac. Check that the location is where you are.")
                }
            }
            if status == .pending {
                decisionSection(summary)
            } else {
                Section { statusNote(status) }
            }
        }
        .disabled(model.isDeciding)
    }

    private func decisionSection(_ summary: SigninRequestSummary) -> some View {
        Section {
            Button {
                Task { await model.approve() }
            } label: {
                HStack {
                    Text("Approve")
                    Spacer()
                    if model.isDeciding { ProgressView() }
                }
            }
            .accessibilityIdentifier("mac-signin.approve")
            Button("Reject…", role: .destructive) { confirmsReject = true }
        }
        .confirmationDialog("Reject \(summary.deviceLabel)?", isPresented: $confirmsReject,
                            titleVisibility: .visible) {
            Button("Reject", role: .destructive) { Task { await model.reject() } }
        } message: {
            Text("The Mac will not be signed in. It can ask again with a new code.")
        }
    }

    private func statusNote(_ status: SigninProgress) -> some View {
        Label {
            switch status {
            case .approved: Text("This request was already approved.")
            case .rejected: Text("This request was rejected.")
            case .completed: Text("This Mac is already signed in.")
            case .expired, .pending: Text("This request expired. Start again on the Mac.")
            }
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(Theme.ink2)
        .accessibilityIdentifier("mac-signin.status")
    }

    private func outcome(_ title: Text, systemImage: String) -> some View {
        ContentUnavailableView {
            Label { title } icon: { Image(systemName: systemImage) }
        } actions: {
            Button("Scan Again") { model.reset() }
                .accessibilityIdentifier("mac-signin.scan-again")
        }
        .accessibilityIdentifier("mac-signin.outcome")
    }

    private func scanDemoLinkIfPresent() {
        guard isDemoMode, let rawValue = ProcessInfo.processInfo.environment["HIBOSS_DEMO_SIGNIN_SCAN"],
              !rawValue.isEmpty else { return }
        _ = model.accept(scanned: rawValue)
    }
}
