// Today working sessions and delivered messages with their attachment previews.
// Exports TodayResults, using the shared projection without sorting.
// Dependencies: SwiftUI, HibossKit, SessionRoute, MessageAttachmentView, and Theme.

import HibossKit
import SwiftUI

struct TodayResults: View {
    @Environment(\.projectSessions) private var inventory
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !snapshot.working.isEmpty {
                section(Text("Working now")) {
                    ForEach(snapshot.working) { session in
                        NavigationLink(value: SessionRoute(id: session.id, label: session.projectLabel)) {
                            sessionRow(session)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !snapshot.delivered.isEmpty {
                section(Text("Delivered")) {
                    ForEach(snapshot.delivered) { message in
                        deliveredRow(message)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func section<Content: View>(
        _ title: Text, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title.font(.title3.bold())
            content()
        }
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        HStack(spacing: 12) {
            ProjectAvatarView(project: inventory.first { $0.id == session.id }?.avatarProject
                              ?? .fallback(session.projectLabel), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: [inventory.first { $0.id == session.id }?.namedLabel ?? session.projectLabel,
                                session.branch, session.agentName]
                    .compactMap { $0 }.joined(separator: " · ")).font(.subheadline.bold())
                Text(verbatim: session.statusText).font(.footnote).foregroundStyle(Theme.ink2)
                if let date = session.lastActivityDate {
                    Text(date, style: .relative).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func deliveredRow(_ message: HistoryMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let attachment = message.metadata?.attachment {
                attachmentThumbnail(attachment)
            }
            NavigationLink(value: message.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: message.body).font(.subheadline.weight(.semibold))
                    HStack(alignment: .top, spacing: 6) {
                        ProjectAvatarView(project: inventory.first {
                            $0.id == message.sessionId
                        }?.avatarProject
                                          ?? inventory.project(slug: message.project ?? ""), size: 24)
                        Text(verbatim: [inventory.first { $0.id == message.sessionId }?.namedLabel
                                       ?? message.project, message.sessionBranch, message.displayName]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.ink2)
                    }
                    if let attachment = message.metadata?.attachment, attachment.kind == .file {
                        Text(verbatim: attachment.filename).font(.footnote).foregroundStyle(Theme.ink2)
                            .accessibilityIdentifier("today-delivered-filename")
                    }
                    if let date = message.createdDate {
                        Text(date, style: .relative).font(.caption).foregroundStyle(Theme.ink3)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
        .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private func attachmentThumbnail(_ attachment: MessageAttachment) -> some View {
        switch attachment.kind {
        case .image:
            MessageAttachmentView(attachment: attachment).frame(width: 72, height: 72).clipped()
        case .file:
            Link(
                destination: attachment.url
            ) {
                Image(systemName: "doc").font(.title2)
                    .frame(width: 72, height: 72)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(Text(verbatim: attachment.filename))
        }
    }

}
