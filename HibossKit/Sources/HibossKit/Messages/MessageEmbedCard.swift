// Draws a hiboss-embed card like a Discord embed: coloured edge, title, fields in rows, footer.
// Exports MessageEmbedCard for iOS and macOS message details and transcripts.
// Dependencies: SwiftUI, MessageEmbed, and MessageMarkdown for the Markdown text values.

import SwiftUI

public struct MessageEmbedCard: View {
    private let embed: MessageEmbed

    public init(_ embed: MessageEmbed) { self.embed = embed }

    public var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(edge).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                header
                if let description = embed.description {
                    MessageMarkdownView(description)
                }
                ForEach(Array(embed.fieldRows.enumerated()), id: \.offset) { _, row in
                    fieldRow(row)
                }
                ForEach([embed.image, embed.thumbnail].compactMap { $0 }, id: \.self) { url in
                    Link(url.absoluteString, destination: url).font(.caption).lineLimit(1)
                }
                footer
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Hashes and addresses wrap without hyphens, which would read as part of the value.
            .typesettingLanguage(Locale.Language(identifier: "zxx"))
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message-embed-card")
    }

    private var edge: Color {
        guard let color = embed.color else { return Color.secondary.opacity(0.35) }
        return Color(red: Double((color >> 16) & 0xff) / 255, green: Double((color >> 8) & 0xff) / 255,
                     blue: Double(color & 0xff) / 255)
    }

    @ViewBuilder private var header: some View {
        if let author = embed.author {
            Text(MessageMarkdown.inline(author)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        if let title = embed.title {
            Text(titleText(title)).font(.headline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func titleText(_ title: String) -> AttributedString {
        var text = MessageMarkdown.inline(title)
        if let url = embed.url {
            text.link = url
            text.swiftUI.underlineStyle = .single
        }
        return text
    }

    /// An inline row keeps three equal columns, so values line up from row to row.
    private func fieldRow(_ row: [MessageEmbed.Field]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 2) {
                    if !field.name.isEmpty {
                        Text(MessageMarkdown.inline(field.name)).font(.subheadline.weight(.semibold))
                    }
                    Text(MessageMarkdown.inline(field.value)).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if row.first?.inline == true {
                ForEach(row.count..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private var footer: some View {
        if embed.footer != nil || embed.timestamp != nil {
            HStack(spacing: 4) {
                if let footer = embed.footer { Text(MessageMarkdown.inline(footer)) }
                if embed.footer != nil, embed.timestamp != nil { Text(verbatim: "·") }
                if let timestamp = embed.timestamp {
                    Text(timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
