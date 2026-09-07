// Message-first history detail with wrapping content and recoverable custom replies.
// Exports: HistoryMessageDetail and its message-first section policy.
// Dependencies: SwiftUI, HibossKit, HistoryMessageLogic, AttentionReplyState.

import HibossKit
import SwiftUI

enum HistoryDetailSection: Hashable {
    case message, choices, metadata
}

enum HistoryDetailLayout {
    static let showsMetadataByDefault = false

    static func sections(hasChoices: Bool) -> [HistoryDetailSection] {
        hasChoices ? [.message, .choices, .metadata] : [.message, .metadata]
    }
}

struct HistoryMessageDetail: View {
    let message: HistoryMessage
    @ObservedObject var reply: AttentionReplyState
    let onChoose: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showsMetadata = HistoryDetailLayout.showsMetadataByDefault

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(HistoryDetailLayout.sections(hasChoices: !message.options.isEmpty), id: \.self) {
                    detailSection($0)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if message.isBlockingHistoryMessage {
                AttentionReplyComposer(text: Binding(
                    get: { reply.drafts[message.id] ?? "" }, set: { reply.drafts[message.id] = $0 }),
                    isSubmitting: reply.submitting.contains(message.id), error: reply.errors[message.id],
                    onSend: { send(reply.drafts[message.id] ?? "") })
            }
        }
        .frame(minWidth: 360, idealWidth: 520, minHeight: 320, idealHeight: 520)
        .navigationTitle(L("Message details"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Close")) { dismiss() }
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ section: HistoryDetailSection) -> some View {
        switch section {
        case .message:
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Message")).font(.headline)
                Text(message.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let content = cleaned(message.content) {
                    Text(content).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        case .choices:
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Choices")).font(.headline)
                ForEach(message.options, id: \.self) { option in choice(option) }
            }
        case .metadata:
            DisclosureGroup(L("Details"), isExpanded: $showsMetadata) {
                metadataContent
            }
        }
    }

    private var metadataContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow(L("From"), value: message.historyDisplayName)
            metadataRow(L("Status"), value: message.status)
            metadataRow(L("Priority"), value: message.priority)
            if let channel = cleaned(message.channel) { metadataRow(L("Channel"), value: channel) }
            if let mode = cleaned(message.mode) { metadataRow(L("Mode"), value: mode) }
            if let session = cleaned(message.sessionLabel) ?? cleaned(message.sessionBranch) {
                metadataRow(L("Session"), value: session)
            }
            metadataRow(L("Created"), value: message.createdAt)
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func choice(_ option: String) -> some View {
        if message.isBlockingHistoryMessage {
            Button { send(option) } label: {
                Text(option).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).disabled(reply.submitting.contains(message.id))
        } else {
            Label(option, systemImage: option == message.defaultOption ? "return" : "circle")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func send(_ text: String) {
        Task {
            await reply.send(text, for: message.id) { text, _ in
                let succeeded = await onChoose(text)
                if succeeded { dismiss() }
                return succeeded
            }
        }
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
