// Verifies hiboss-embed cards: tolerant decoding, Discord field rows, fence parsing and fallbacks.
// Exercises MessageEmbed, MessageMarkdown block kinds and the rich_content preference.
// Dependencies: XCTest and HibossKit.

import SwiftUI
import XCTest
@testable import HibossKit

final class MessageEmbedTests: XCTestCase {
    private let card = #"{"color":3447003,"title":"Order Filled","url":"https://bscscan.com/tx/0x1","fields":[{"name":"tx","value":"[0x75](https://bscscan.com/tx/0x75)","inline":true},{"name":"order","value":"0xaf","inline":true},{"name":"provider","value":"SmartRouter","inline":true},{"name":"gas","value":"0.000024 BNB","inline":true},{"name":"net","value":"$0.0270","inline":false}],"footer":"PCSX Filler","timestamp":"2026-11-24T08:32:00.000Z"}"#

    func testDecodesACardAndGroupsInlineFieldsThreePerRow() throws {
        let embed = try XCTUnwrap(MessageEmbed.decode(card))
        XCTAssertEqual(embed.color, 0x3498DB)
        XCTAssertEqual(embed.url?.host, "bscscan.com")
        XCTAssertEqual(embed.fieldRows.map { $0.map(\.name) }, [["tx", "order", "provider"], ["gas"], ["net"]])
        XCTAssertNotNil(embed.timestamp)
    }

    func testToleratesMissingValuesAndRejectsUnsafeLinks() throws {
        let embed = try XCTUnwrap(MessageEmbed.decode(#"{"title":"x","url":"javascript:alert(1)","fields":[{"value":"v"}],"timestamp":"nope"}"#))
        XCTAssertNil(embed.url)
        XCTAssertEqual(embed.fields, [.init(name: "", value: "v", inline: false)])
        XCTAssertNil(embed.timestamp)
        XCTAssertNil(MessageEmbed.decode("not json"))
    }

    func testOnlyAClosedHibossEmbedFenceIsACard() {
        let blocks = MessageMarkdown.blocks("Lead\n\n```hiboss-embed\n\(card)\n```\n\n```hiboss-embed\n{}")
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .embed, .code])
        XCTAssertEqual(blocks[1].text, card)
        XCTAssertEqual(MessageMarkdown.blocks("```hiboss-embedded\n{}\n```").map(\.kind), [.code])
    }

    /// A long hash wraps inside its column, so a narrow card grows taller instead of clipping.
    @MainActor func testCardRendersAndWrapsLongValuesAtNarrowWidths() throws {
        let embed = try XCTUnwrap(MessageEmbed.decode(card))
        func height(_ width: CGFloat) -> CGFloat {
            let renderer = ImageRenderer(content: MessageEmbedCard(embed).frame(width: width))
            return renderer.cgImage.map { CGFloat($0.height) / renderer.scale } ?? 0
        }
        let wide = height(640)
        XCTAssertGreaterThan(wide, 100)
        XCTAssertGreaterThan(height(240), wide)
    }

    func testATextBlockIsPlainTextAndACardIsNot() throws {
        let text = try XCTUnwrap(MessageEmbed.decode(#"{"text":"Deploy finished \u0060rm\u0060"}"#))
        XCTAssertTrue(text.isTextOnly)
        XCTAssertEqual(text.text, "Deploy finished `rm`")
        XCTAssertFalse(try XCTUnwrap(MessageEmbed.decode(card)).isTextOnly)
    }

    /// Text inside a card renders with cards off, so a fence in a description stays code.
    @MainActor func testTextInsideACardCannotDrawAnotherCard() {
        let nested = "```hiboss-embed\n\(card)\n```"
        func height(_ view: some View) -> CGFloat {
            let renderer = ImageRenderer(content: view.frame(width: 400))
            return renderer.cgImage.map { CGFloat($0.height) / renderer.scale } ?? 0
        }
        XCTAssertNotEqual(height(MessageMarkdownView(nested)), height(MessageMarkdownView(nested, cards: false)))
    }

    func testRichContentIsShownInsteadOfThePlainFallback() throws {
        let json = #"{"content":"plain","rich_content":"```hiboss-embed\n{}\n```"}"#
        let metadata = try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
        XCTAssertEqual(metadata.content, "plain")
        XCTAssertEqual(metadata.richContent, "```hiboss-embed\n{}\n```")
    }
}
