// Today working sessions and delivered messages with their attachment previews.
// Exports TodayResults: content-first rows with one identity line, using the shared projection.
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

    /// Content first: the latest status leads, one meta line carries who and when.
    private func sessionRow(_ session: TodaySession) -> some View {
        let inventoryRow = inventory.first { $0.id == session.id }
        let identity = TodayRowIdentity.make(
            label: inventoryRow?.label, fallback: session.projectLabel, nickname: inventoryRow?.nickname,
            branch: session.branch, host: inventoryRow?.host, agent: session.agentName)
        return HStack(alignment: .top, spacing: Space.s) {
            TodayRowAvatar(project: inventoryRow?.avatarProject ?? .fallback(session.projectLabel),
                           agent: session.agentName, lookupName: session.agentName)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: session.statusText.isEmpty ? identity.project : session.statusText)
                    .font(.hbSmall).foregroundStyle(Theme.ink).lineLimit(2)
                metaLine(identity, date: session.lastActivityDate, working: true)
            }
            Spacer(minLength: 0)
            SessionReadIndicator(sessionID: session.id, needsYou: session.needsYou,
                                 window: session.decisionWindow)
            disclosure.padding(.top, Space.xxs)
        }
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
        .padding(Space.s)
    }

    private func deliveredRow(_ message: HistoryMessage) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            NavigationLink(value: message.id) {
                HStack(alignment: .top, spacing: Space.s) {
                    TodayRowAvatar(project: deliveredProject(message), agent: message.displayName,
                                   lookupName: message.agentName)
                    deliveredText(message)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
            }
            .buttonStyle(TodayRowButtonStyle())
            if let attachment = message.metadata?.attachment {
                attachmentThumbnail(attachment)
            }
            // The chevron ends every row at the same edge, after any thumbnail.
            NavigationLink(value: message.id) { disclosure.padding(.top, Space.xxs) }
                .buttonStyle(TodayRowButtonStyle())
                .accessibilityHidden(true)
        }
        .padding(Space.s)
    }

    private func deliveredProject(_ message: HistoryMessage) -> ProjectIdentity {
        inventory.first { $0.id == message.sessionId }?.avatarProject
            ?? inventory.project(slug: message.project ?? "")
    }

    private func deliveredText(_ message: HistoryMessage) -> some View {
        let inventoryRow = inventory.first { $0.id == message.sessionId }
        let identity = TodayRowIdentity.make(
            label: inventoryRow?.label ?? message.sessionLabel, fallback: message.project ?? message.displayName,
            nickname: inventoryRow?.nickname, branch: message.sessionBranch, host: inventoryRow?.host,
            agent: message.displayName)
        return VStack(alignment: .leading, spacing: Space.xxs) {
            Text(verbatim: message.body).font(.hbSmall.weight(.semibold)).foregroundStyle(Theme.ink)
                .lineLimit(3)
            MessageReactions(message: message)
            if let attachment = message.metadata?.attachment, attachment.kind == .file {
                Text(verbatim: attachment.filename).font(.hbFootnote).foregroundStyle(Theme.ink2)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityIdentifier("today-delivered-filename")
            }
            metaLine(identity, date: message.createdDate, working: false)
        }
    }

    /// One line: project in emphasis, then nickname, branch and device, then the time,
    /// which never truncates; the identity gives way first.
    private func metaLine(_ identity: TodayRowIdentity, date: Date?, working: Bool) -> some View {
        HStack(spacing: Space.xxs) {
            if working {
                Circle().fill(Theme.positive).frame(width: 7, height: 7).accessibilityHidden(true)
            }
            (Text(verbatim: identity.project).fontWeight(.semibold).foregroundColor(Theme.ink2)
                + Text(verbatim: identity.detail.isEmpty ? "" : " · " + identity.detail.joined(separator: " · ")))
                .lineLimit(1).truncationMode(.tail)
                .accessibilityLabel(Text(verbatim: identity.text))
            if let date {
                Text(verbatim: "·").accessibilityHidden(true)
                RecordedTimeText(date: date).fixedSize().layoutPriority(1)
            }
        }
        .font(.hbFootnote).foregroundStyle(Theme.ink3)
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink3)
            .accessibilityHidden(true)
    }

    /// Trailing, so every row's text starts at the same edge.
    private let thumbnailSide: CGFloat = 48

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
    }

    @ViewBuilder private func attachmentThumbnail(_ attachment: MessageAttachment) -> some View {
        switch attachment.kind {
        case .image:
            MessageAttachmentView(attachment: attachment).frame(width: thumbnailSide, height: thumbnailSide)
                .clipShape(mediaShape)
        case .file:
            if MediaFileKind.kind(filename: attachment.filename) != nil {
                MessageAttachmentView(attachment: attachment).frame(width: thumbnailSide, height: thumbnailSide)
                    .clipShape(mediaShape)
            } else {
                Link(
                    destination: attachment.url
                ) {
                    Image(systemName: "doc").font(.title3)
                        .frame(width: thumbnailSide, height: thumbnailSide)
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
