// Today working sessions and delivered messages with their attachment previews.
// Exports TodayResults, using the shared projection without sorting.
// Dependencies: SwiftUI, HibossKit, SessionRoute, MessageAttachmentView, and Theme.

import HibossKit
import SwiftUI

struct TodayResults: View {
    @Environment(\.projectSessions) private var inventory
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if !snapshot.working.isEmpty {
                section(Text("Working now")) {
                    ForEach(Array(snapshot.working.enumerated()), id: \.element.id) { index, session in
                        if index > 0 { rowDivider }
                        NavigationLink(value: SessionRoute(id: session.id, label: session.projectLabel)) {
                            sessionRow(session)
                        }
                        .buttonStyle(TodayRowButtonStyle())
                        .accessibilityIdentifier("today-working-\(session.id)")
                    }
                }
            }
            if !snapshot.delivered.isEmpty {
                section(Text("Delivered")) {
                    ForEach(Array(snapshot.delivered.enumerated()), id: \.element.id) { index, message in
                        if index > 0 { rowDivider }
                        deliveredRow(message)
                    }
                }
            }
        }
        .padding(.horizontal, Space.m)
    }

    /// Grouped separator, inset from the card edge. Leading tiles differ in width.
    private var rowDivider: some View {
        Divider().padding(.leading, Space.m)
    }

    /// A secondary list under Today's primary section: a footnote header and one grouped card.
    private func section<Content: View>(
        _ title: Text, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            title.font(.hbFootnote).foregroundStyle(Theme.ink2).accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Space.s)
            VStack(spacing: 0) { content() }
                .background(Theme.surface, in: groupedShape)
                .clipShape(groupedShape)
        }
    }

    private var groupedShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
    }

    private func sessionRow(_ session: TodaySession) -> some View {
        HStack(spacing: Space.s) {
            ProjectAvatarView(project: inventory.first { $0.id == session.id }?.avatarProject
                              ?? .fallback(session.projectLabel), size: AvatarSize.row)
            if let agent = session.agentName { AgentAvatarView(name: agent, size: AvatarSize.inline) }
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: [inventory.first { $0.id == session.id }?.namedLabel ?? session.projectLabel,
                                session.branch, session.agentName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.hbSmall.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(verbatim: session.statusText).font(.hbFootnote).foregroundStyle(Theme.positive)
                if let date = session.lastActivityDate {
                    RecordedTimeText(date: date).font(.hbCaption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou)
            disclosure
        }
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
        .padding(Space.s)
    }

    private func deliveredRow(_ message: HistoryMessage) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            if let attachment = message.metadata?.attachment {
                attachmentThumbnail(attachment)
            }
            NavigationLink(value: message.id) {
                HStack(alignment: .top, spacing: Space.xs) {
                    deliveredText(message)
                    disclosure.padding(.top, Space.xxs)
                }
                .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
            }
            .buttonStyle(TodayRowButtonStyle())
        }
        .padding(Space.s)
    }

    private func deliveredText(_ message: HistoryMessage) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(verbatim: message.body).font(.hbSmall.weight(.semibold)).foregroundStyle(Theme.ink)
            MessageReactions(message: message)
            HStack(alignment: .top, spacing: Space.xxs) {
                ProjectAvatarView(project: inventory.first {
                    $0.id == message.sessionId
                }?.avatarProject
                                  ?? inventory.project(slug: message.project ?? ""), size: AvatarSize.inline)
                AgentAvatarView(name: message.displayName, size: AvatarSize.inline, lookupName: message.agentName)
                Text(verbatim: [inventory.first { $0.id == message.sessionId }?.namedLabel
                               ?? message.project, message.sessionBranch, message.displayName]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.hbFootnote).foregroundStyle(Theme.ink2)
            }
            if let attachment = message.metadata?.attachment, attachment.kind == .file {
                Text(verbatim: attachment.filename).font(.hbFootnote).foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("today-delivered-filename")
            }
            if let date = message.createdDate {
                RecordedTimeText(date: date).font(.hbCaption).foregroundStyle(Theme.ink3)
            }
        }
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink3)
            .accessibilityHidden(true)
    }

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
    }

    @ViewBuilder private func attachmentThumbnail(_ attachment: MessageAttachment) -> some View {
        switch attachment.kind {
        case .image:
            MessageAttachmentView(attachment: attachment).frame(width: 72, height: 72).clipShape(mediaShape)
        case .file:
            if MediaFileKind.kind(filename: attachment.filename) != nil {
                MessageAttachmentView(attachment: attachment).frame(width: 72, height: 72).clipShape(mediaShape)
            } else {
                Link(
                    destination: attachment.url
                ) {
                    Image(systemName: "doc").font(.title2)
                        .frame(width: 72, height: 72)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Radius.medium,
                                                                        style: .continuous))
                }
                .accessibilityLabel(Text(verbatim: attachment.filename))
            }
        }
    }

}

/// Pressed rows darken in place. Plain buttons would drop that cue.
private struct TodayRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.surface2 : Color.clear)
    }
}
