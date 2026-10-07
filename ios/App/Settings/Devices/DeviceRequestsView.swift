// Settings > Device Requests: machines waiting to join, with pull-to-refresh and review sheets.
// Exports: DeviceRequestsView.
// Dependencies: SwiftUI, Theme tokens, HibossKit's JoinRequestsModel, and JoinRequestReviewView.

import HibossKit
import SwiftUI

struct DeviceRequestsView: View {
    @ObservedObject var model: JoinRequestsModel
    @State private var target: JoinRequestTarget?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            content
            if case .failed = model.state { retryButton }
            if !model.requests.isEmpty, model.state == .loading {
                SettingsWaitView(title: "Loading device requests…") { dismiss() }
            }
        }
        .navigationTitle("Device Requests")
        .refreshable { await model.refresh() }
        .task { await model.refresh() }
        .sheet(item: $target) { target in
            NavigationStack { JoinRequestReviewView(requestID: target.id, model: model) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isForbidden {
            ContentUnavailableView {
                Label("Only an admin can approve devices", systemImage: "person.badge.key")
            } description: {
                Text("Ask an admin of this HiBoss server to approve new machines.")
            }
        } else if model.requests.isEmpty {
            emptyContent
        } else {
            Section {
                ForEach(model.requests) { request in
                    Button { target = JoinRequestTarget(id: request.id) } label: { row(request) }
                        .foregroundStyle(Theme.ink)
                }
            } footer: {
                if case let .failed(message) = model.state { Text(verbatim: message) }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch model.state {
        case .loading, .idle:
            SettingsWaitView(title: "Loading device requests…") { dismiss() }
        case let .failed(message):
            ContentUnavailableView {
                Label("Device requests unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            }
        case .loaded, .forbidden:
            ContentUnavailableView {
                Label("No device requests", systemImage: "desktopcomputer")
            } description: {
                Text("New machines appear here when they ask to join.")
            }
        }
    }

    private var retryButton: some View {
        Button("Try again") { Task { await model.refresh() } }
    }

    private func row(_ request: JoinRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer").foregroundStyle(Theme.ink2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: request.deviceLabel).font(.hbBodyStrong)
                if let detail = detail(request) {
                    Text(verbatim: detail).font(.hbSmall).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                if let note = Self.approvalNote(request) {
                    // Words and a glyph, not color alone, say this row cannot be approved.
                    Label { Text(note) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.hbSmall)
                        .foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: 8)
            if let created = request.createdDate {
                Text(created, format: .relative(presentation: .named))
                    .font(.hbCaption).foregroundStyle(Theme.ink2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(request.canApprove
            ? Text("Shows the verification code") : Text("Shows the request details"))
    }

    /// Why a request cannot be approved, shown on its row; nil when it can be.
    nonisolated static func approvalNote(_ request: JoinRequest) -> LocalizedStringResource? {
        request.canApprove ? nil : "No verification code — can’t be approved"
    }

    private func detail(_ request: JoinRequest) -> String? {
        let parts = [request.deviceHost, request.profiles.isEmpty ? nil : request.profileSummary]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
