// Approval sheet for one machine join request; pending decisions retain the verification code.
// Exports: JoinRequestReviewView, presented from a push tap or Settings > Device Requests.
// Dependencies: SwiftUI, Theme tokens, and HibossKit's JoinRequestReview.

import HibossKit
import SwiftUI

struct JoinRequestReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var review: JoinRequestReview
    @State private var confirmsReject = false

    init(requestID: String, model: JoinRequestsModel) {
        _review = StateObject(wrappedValue: JoinRequestReview(requestID: requestID, model: model))
    }

    var body: some View {
        content
            .navigationTitle("Device Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { isFinished ? Text("Done") : Text("Close") }
                }
            }
            .task { await review.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch review.phase {
        case .loading:
            SettingsWaitView(title: "Loading request…") { dismiss() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .ready(request):
            requestForm(request)
        case let .approved(request, approval):
            outcome(request: request, approval: approval)
        case let .rejected(request):
            outcome(request: request, approval: nil)
        case let .unavailable(message):
            ContentUnavailableView {
                Label("Request unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            } actions: {
                Button("Try again") { Task { await review.load() } }
            }
        }
    }

    private var isFinished: Bool {
        switch review.phase {
        case .approved, .rejected: true
        default: false
        }
    }

    private func requestForm(_ request: JoinRequest) -> some View {
        Form {
            codeSection(request)
            Section("Device") {
                LabeledContent("Name") { Text(verbatim: request.deviceLabel) }
                LabeledContent("Host") { Text(verbatim: request.deviceHost ?? "—") }
                if let inviter = request.inviterLabel {
                    Text("Invited from \(inviter)").foregroundStyle(Theme.ink2)
                }
                if let created = request.createdDate {
                    LabeledContent("Requested") { Text(created, format: .relative(presentation: .named)) }
                }
            }
            Section("Profiles") {
                if request.profiles.isEmpty { Text("No profiles").foregroundStyle(Theme.ink2) }
                ForEach(request.profiles) { profile in
                    LabeledContent { Text(verbatim: profile.profile) } label: { Text(verbatim: profile.name) }
                }
            }
            decisionSection(request)
        }
        .confirmationDialog("Reject \(request.deviceLabel)?", isPresented: $confirmsReject,
                            titleVisibility: .visible) {
            Button("Reject", role: .destructive) { Task { await review.reject() } }
        } message: {
            Text("The machine will not join. It can send a new request later.")
        }
    }

    private func codeSection(_ request: JoinRequest) -> some View {
        Section {
            if let code = request.displayCode {
                Text(verbatim: code)
                    .font(.hbCode)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityLabel(
                        Text("Verification code \(code.map(String.init).joined(separator: " "))"))
                    .accessibilityIdentifier("join-request.code")
            } else {
                Label("This request has no verification code, so it can’t be approved here.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.ink2)
            }
        } header: {
            Text("Verification code")
        } footer: {
            if request.canApprove { Text("Approve only if the new machine shows this code") }
        }
    }

    private func decisionSection(_ request: JoinRequest) -> some View {
        Section {
            Button {
                Task { await review.approve() }
            } label: {
                HStack {
                    Text("Approve")
                    Spacer()
                }
            }
            .disabled(!request.canApprove || review.isDeciding)
            .accessibilityIdentifier("join-request.approve")
            Button("Reject…", role: .destructive) { confirmsReject = true }
                .disabled(review.isDeciding)
        } footer: {
            if review.isDeciding {
                SettingsWaitView(title: "Sending your decision…") { dismiss() }
            }
            if let failure = review.failureMessage {
                Label { Text(verbatim: failure) } icon: { Image(systemName: "xmark.octagon") }
                    .foregroundStyle(Theme.negative)
            }
        }
    }

    private func outcome(request: JoinRequest, approval: JoinApproval?) -> some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: approval == nil ? "xmark.circle" : "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(approval == nil ? Theme.ink2 : Theme.positive)
                    (approval == nil ? Text("\(request.deviceLabel) was rejected")
                        : Text("\(request.deviceLabel) can now join"))
                        .font(.hbH2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
            if let approval, !approval.agents.isEmpty {
                Section("Agents") {
                    ForEach(approval.agents) { agent in
                        LabeledContent { Text(verbatim: agent.profile) } label: { Text(verbatim: agent.name) }
                    }
                }
            }
        }
    }
}
