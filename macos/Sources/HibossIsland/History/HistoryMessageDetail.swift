// Full History message detail presented from a double-clicked list row.
// Exports: HistoryMessageDetail and its message-first layout policy.
// Dependencies: SwiftUI, HibossKit HistoryMessage, and HistoryMessageLogic.

import HibossKit
import SwiftUI

enum HistoryDetailSection: Hashable {
    case message
    case choices
    case metadata
}

enum HistoryDetailLayout {
    static let showsMetadataByDefault = false

    static func sections(hasChoices: Bool) -> [HistoryDetailSection] {
        hasChoices ? [.message, .choices, .metadata] : [.message, .metadata]
    }
}

struct HistoryMessageDetail: View {
    let message: HistoryMessage
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsMetadata = HistoryDetailLayout.showsMetadataByDefault

    var body: some View {
        Form {
            ForEach(
                HistoryDetailLayout.sections(hasChoices: !message.options.isEmpty),
                id: \.self
            ) { section in
                detailSection(section)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 560)
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
            Section(L("Message")) { messageContent }
        case .choices:
            Section(L("Choices")) {
                ForEach(message.options, id: \.self) { option in choice(option) }
            }
        case .metadata:
            Section {
                DisclosureGroup(L("Details"), isExpanded: $showsMetadata) {
                    metadataContent
                }
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        Text(message.body)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let content = cleaned(message.content) {
            Text(content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataContent: some View {
        LabeledContent(L("From"), value: message.historyDisplayName)
        LabeledContent(L("Status"), value: message.status)
        LabeledContent(L("Priority"), value: message.priority)
        if let channel = cleaned(message.channel) {
            LabeledContent(L("Channel"), value: channel)
        }
        if let mode = cleaned(message.mode) {
            LabeledContent(L("Mode"), value: mode)
        }
        if let session = cleaned(message.sessionLabel) ?? cleaned(message.sessionBranch) {
            LabeledContent(L("Session"), value: session)
        }
        LabeledContent(L("Created"), value: message.createdAt)
    }

    @ViewBuilder
    private func choice(_ option: String) -> some View {
        if message.isBlockingHistoryMessage {
            Button {
                onChoose(option)
                dismiss()
            } label: {
                HStack {
                    if option == message.defaultOption { Image(systemName: "return") }
                    Text(option)
                    Spacer()
                }
            }
        } else {
            Label(option, systemImage: option == message.defaultOption ? "return" : "circle")
                .foregroundStyle(.secondary)
        }
    }

    private func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
