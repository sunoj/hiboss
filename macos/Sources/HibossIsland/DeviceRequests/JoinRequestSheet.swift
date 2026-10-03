// Approval sheet for one machine join request; the verification code is always on screen.
// Exports: JoinRequestSheet.
// Dependencies: SwiftUI and HibossKit's JoinRequestReview and JoinRequestsModel.

import HibossKit
import SwiftUI

struct JoinRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var review: JoinRequestReview
    @State private var confirmsReject = false

    init(requestID: String, model: JoinRequestsModel) {
        _review = StateObject(wrappedValue: JoinRequestReview(requestID: requestID, model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            buttonBar
                .padding(16)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 540)
        .task { await review.load() }
        .confirmationDialog(rejectTitle, isPresented: $confirmsReject, titleVisibility: .visible) {
            Button(L("Reject"), role: .destructive) { Task { await review.reject() } }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The machine will not join. It can send a new request later."))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch review.phase {
        case .loading:
            ProgressView(L("Loading request…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(request):
            requestForm(request)
        case let .approved(request, approval):
            JoinRequestOutcome(request: request, approval: approval)
        case let .rejected(request):
            JoinRequestOutcome(request: request, approval: nil)
        case let .unavailable(message):
            ContentUnavailableView(L("Request unavailable"), systemImage: "exclamationmark.triangle",
                description: Text(verbatim: message))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func requestForm(_ request: JoinRequest) -> some View {
        Form {
            Section {
                JoinVerificationCode(request: request)
            } header: {
                Text(L("Verification code"))
            } footer: {
                if request.canApprove {
                    Text(L("Approve only if the new machine shows this code"))
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Device")) {
                LabeledContent(L("Name")) { Text(verbatim: request.deviceLabel) }
                LabeledContent(L("Host")) { Text(verbatim: request.deviceHost ?? "—") } // i18n-exempt: placeholder dash
                if let inviter = request.inviterLabel {
                    Text(L("Invited from \(inviter)")).foregroundStyle(.secondary)
                }
                if let created = request.createdDate {
                    LabeledContent(L("Requested")) { Text(created, format: .relative(presentation: .named)) }
                }
            }
            Section(L("Profiles")) {
                if request.profiles.isEmpty {
                    Text(L("No profiles")).foregroundStyle(.secondary)
                }
                ForEach(request.profiles) { profile in
                    LabeledContent { Text(verbatim: profile.profile) } label: { Text(verbatim: profile.name) }
                }
            }
            if let failure = review.failureMessage {
                Section { Label(failure, systemImage: "xmark.octagon").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .disabled(review.isDeciding)
    }

    @ViewBuilder
    private var buttonBar: some View {
        HStack {
            if case let .ready(request) = review.phase {
                Button(L("Reject…"), role: .destructive) { confirmsReject = true }
                    .disabled(review.isDeciding)
                Spacer()
                if review.isDeciding { ProgressView().controlSize(.small) }
                Button(L("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // Deliberately no default-action shortcut: approval is a click on this button only.
                Button(L("Approve")) { Task { await review.approve() } }
                    .disabled(!request.canApprove || review.isDeciding)
                    .accessibilityIdentifier("join-request.approve")
            } else {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var rejectTitle: String {
        guard case let .ready(request) = review.phase else { return L("Reject this device?") }
        return L("Reject \(request.deviceLabel)?")
    }
}

/// The code in large monospaced digits, or why approval is unavailable without one.
private struct JoinVerificationCode: View {
    let request: JoinRequest

    var body: some View {
        if let code = request.displayCode {
            Text(verbatim: code)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityLabel(L("Verification code \(code.map(String.init).joined(separator: " "))"))
                .accessibilityIdentifier("join-request.code")
        } else {
            Label(L("This request has no verification code, so it can’t be approved here."),
                systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct JoinRequestOutcome: View {
    let request: JoinRequest
    let approval: JoinApproval?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: approval == nil ? "xmark.circle" : "checkmark.circle.fill")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundStyle(approval == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(DesignTokens.live))
                    Text(approval == nil ? L("\(request.deviceLabel) was rejected")
                        : L("\(request.deviceLabel) can now join"))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            if let approval, !approval.agents.isEmpty {
                Section(L("Agents")) {
                    ForEach(approval.agents) { agent in
                        LabeledContent { Text(verbatim: agent.profile) } label: { Text(verbatim: agent.name) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
