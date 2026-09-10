// Selected attention item: wrapping question, native choices, and supporting metadata.
// Exports: AttentionDetail.
// Dependencies: SwiftUI, AttentionItem; reply composer is owned by AttentionWorkspace.

import HibossKit
import SwiftUI

struct AttentionDetail: View {
    let item: AttentionItem
    let now: Date
    let onChoose: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                question
                if !item.options.isEmpty { choices }
                metadata
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Question")).font(.headline)
            Text(item.body)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let content = item.content {
                Text(content)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Choices")).font(.headline)
            if let media = item.message.metadata?.optionMedia, !media.isEmpty {
                OptionMediaPicker(
                    options: item.options,
                    media: media,
                    defaultOption: item.defaultOption,
                    choose: onChoose
                )
            } else {
                ForEach(item.options, id: \.self) { option in
                    Button { onChoose(option) } label: {
                        HStack(alignment: .top) {
                            Text(option)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if option == item.defaultOption, item.isRunningAutoDecision(at: now) {
                                Text(L("default")).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var metadata: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                metadataRow(L("Project"), value: item.project)
                metadataRow(L("From"), value: item.asker)
                TimelineView(.periodic(from: now, by: 1)) { context in
                    timingMetadata(at: context.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private func timingMetadata(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow(L("Waiting"), value: item.waited(at: now))
            if item.isRunningAutoDecision(at: now), let option = item.defaultOption {
                metadataRow(L("Will choose"), value: option)
                if let remaining = item.remaining(at: now) {
                    metadataRow(L("Time left"), value: remaining)
                }
            } else if item.band(at: now) == .blocked {
                metadataRow(L("Status"), value: L("Blocked on you"))
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
