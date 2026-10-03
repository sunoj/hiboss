// Device Requests surface in the main window: pending machines and their approval sheets.
// Exports: DeviceRequestsView and JoinRequestTarget.
// Dependencies: SwiftUI, HibossKit's JoinRequestsModel, and JoinRequestSheet.

import HibossKit
import SwiftUI

struct JoinRequestTarget: Identifiable, Equatable {
    let id: String
}

struct DeviceRequestsView: View {
    @ObservedObject var model: JoinRequestsModel
    @Binding var focus: DeviceRequestsFocus?
    let onSettings: () -> Void
    @State private var target: JoinRequestTarget?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: $target) { JoinRequestSheet(requestID: $0.id, model: model) }
            .onChange(of: focus?.id, initial: true) { openFocusedRequest() }
            .task { await model.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        if model.isForbidden {
            ContentUnavailableView(L("Only an admin can approve devices"), systemImage: "person.badge.key",
                description: Text(L("Ask an admin of this HiBoss server to approve new machines.")))
        } else if model.requests.isEmpty {
            emptyContent
        } else {
            List(model.requests) { request in
                row(request)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { failureNotice }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView {
                Label(L("Connect to HiBoss"), systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text(L("Connect to review device requests."))
            } actions: {
                Button(L("Settings"), action: onSettings)
            }
        case .loading:
            ProgressView(L("Loading device requests…"))
        case let .failed(message):
            ContentUnavailableView {
                Label(L("Device requests unavailable"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(verbatim: message)
            } actions: {
                Button(L("Try again")) { Task { await model.refresh() } }
            }
        case .loaded, .forbidden:
            ContentUnavailableView(L("No device requests"), systemImage: "desktopcomputer",
                description: Text(L("A machine that runs hiboss setup with an invite appears here for approval.")))
        }
    }

    private func row(_ request: JoinRequest) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: request.deviceLabel).font(.headline)
                Text(verbatim: detail(request))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let created = request.createdDate {
                Text(created, format: .relative(presentation: .named))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(L("Review…")) { target = JoinRequestTarget(id: request.id) }
                .accessibilityIdentifier("join-request.review")
        }
        .padding(.vertical, 6)
    }

    private func detail(_ request: JoinRequest) -> String {
        [request.deviceHost, request.profiles.isEmpty ? nil : request.profileSummary]
            .compactMap { $0 }
            .joined(separator: " · ") // i18n-exempt: list separator
    }

    @ViewBuilder
    private var failureNotice: some View {
        if case let .failed(message) = model.state {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.bar)
        }
    }

    private func openFocusedRequest() {
        guard let focus else { return }
        if let id = focus.requestID { target = JoinRequestTarget(id: id) }
        self.focus = nil
    }
}
