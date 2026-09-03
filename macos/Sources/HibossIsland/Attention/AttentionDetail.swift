// Selected attention item: full context and native choice buttons.
// Exports: AttentionDetail.
// Dependencies: SwiftUI, AttentionItem.

import HibossKit
import SwiftUI

struct AttentionDetail: View {
    let item: AttentionItem
    let now: Date
    let onChoose: (String) -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Project"), value: item.project)
                LabeledContent(L("From"), value: item.asker)
                LabeledContent(L("Waiting"), value: item.waited(at: now))
                if item.isRunningAutoDecision(at: now), let option = item.defaultOption {
                    LabeledContent(L("Will choose"), value: option)
                    if let remaining = item.remaining(at: now) {
                        LabeledContent(L("Time left"), value: remaining)
                    }
                } else if item.band(at: now) == .blocked {
                    LabeledContent(L("Status"), value: L("Blocked on you"))
                }
            }

            Section(L("Question")) {
                Text(item.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let content = item.content {
                    Text(content)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.options.isEmpty {
                Section(L("Choices")) {
                    ForEach(item.options, id: \.self) { option in
                        choiceButton(option)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func choiceButton(_ option: String) -> some View {
        let isDefault = option == item.defaultOption
        if isDefault {
            Button {
                onChoose(option)
            } label: {
                HStack {
                    Image(systemName: "return")
                    Text(option)
                    Spacer()
                    if item.isRunningAutoDecision(at: now) {
                        Text(L("default"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .help(L("Default — runs automatically on timeout"))
        } else {
            Button(option) { onChoose(option) }
        }
    }
}
