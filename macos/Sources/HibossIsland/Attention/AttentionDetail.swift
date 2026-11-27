// Selected attention item: wrapping question, native choices, and supporting metadata.
// Exports: AttentionDetail.
// Dependencies: SwiftUI, AttentionItem; reply composer is owned by AttentionWorkspace.

import HibossKit
import SwiftUI

struct AttentionDetail: View {
    @Environment(\.surfaceIsVisible) private var isVisible
    @Environment(\.projectSessions) private var inventory
    let item: AttentionItem
    let now: Date
    var earlier: [HistoryMessage] = []
    var onOpenSession: (() -> Void)?
    let onChoose: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text(verbatim: item.provenance(project: projectName))
                        .font(.caption).foregroundStyle(TodayStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    DecisionDeadline(expiresAt: item.expiresAt, now: now)
                }
                question
                if !item.options.isEmpty { choices(onChoose) }
                if let option = item.defaultOption {
                    DecisionDefaultLine(option: option, expiresAt: item.expiresAt, now: now)
                }
                metadata
                if onOpenSession != nil { sessionContext }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.body)
                .font(.title2.bold())
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
            if let attachment = item.attachment {
                MessageAttachmentView(attachment: attachment)
            }
        }
    }

    private func choices(_ onChoose: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Choices")).font(.headline)
            DecisionChoices(item: item, onChoose: onChoose)
        }
    }

    private var sessionContext: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Earlier in this session")).font(.headline)
            if earlier.isEmpty {
                Text(L("No earlier messages in the loaded history."))
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
            }
            ForEach(earlier) { message in
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.body).font(.callout).textSelection(.enabled)
                    Text(HistoryTimestamp.localDateTime(from: message.createdAt))
                        .font(.caption).foregroundStyle(TodayStyle.tertiary)
                }
                Divider()
            }
            Button(L("Open session"), systemImage: "arrow.up.right") { onOpenSession?() }
        }
    }

    private var projectName: String { item.project(in: inventory).displayName }

    private var metadata: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                metadataRow(L("Project"), value: projectName)
                if let session = item.message.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !session.isEmpty, session != projectName {
                    metadataRow(L("Session"), value: session)
                }
                metadataRow(L("From"), value: item.asker)
                TimelineView(.periodic(from: now, by: 1).paused(!isVisible)) { context in
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
            } else if item.group == .waitingOnYou {
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
