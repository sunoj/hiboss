// Full History message detail presented from a double-clicked list row.
// Exports: HistoryMessageDetail with metadata, content, and active choices.
// Dependencies: SwiftUI, HibossKit HistoryMessage, and HistoryMessageLogic.

import HibossKit
import SwiftUI

struct HistoryMessageDetail: View {
    let message: HistoryMessage
    let onChoose: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent(L("From"), value: message.historyDisplayName)
                LabeledContent(L("Status"), value: message.status)
                LabeledContent(L("Priority"), value: message.priority)
                optionalMetadata
            }

            Section(L("Message")) {
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

            if !message.options.isEmpty {
                Section(L("Choices")) {
                    ForEach(message.options, id: \.self) { option in
                        choice(option)
                    }
                }
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
    private var optionalMetadata: some View {
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
