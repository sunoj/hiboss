// Form asks on the client: decoding metadata.form, completeness, the submitted answer and summary.
// Exports: AskFormTests.
// Dependencies: XCTest and HibossKit's MessageMetadata and AskForm.

import XCTest
@testable import HibossKit

final class AskFormTests: XCTestCase {
    private func metadata(_ json: String) throws -> MessageMetadata {
        try JSONDecoder().decode(MessageMetadata.self, from: Data(json.utf8))
    }

    func testDecodesARankingAndDefaultsItsAnswerToTheShownOrder() throws {
        let meta = try metadata(#"{"options":[],"form":{"catalogVersion":2,"input":{"type":"RankedChoice","props":{"label":"Order","value":{"$bindState":"/form/answer"},"options":[{"id":"a","label":"Alpha"},{"id":"b","label":"Beta"}],"topK":1}}}}"#)
        let form = try XCTUnwrap(meta.form)
        XCTAssertEqual(form.kind, .rankedChoice)
        XCTAssertTrue(form.isComplete(.null))
        XCTAssertEqual(form.answer(from: .null), .array([.string("a")]))
        XCTAssertEqual(form.summary(.array([.string("b")])), "1. Beta")
    }

    func testAReviewIsCompleteOnlyWithEveryVerdictAndRequiredNote() throws {
        let meta = try metadata(#"{"options":[],"form":{"catalogVersion":2,"input":{"type":"ItemReview","props":{"label":"Checks","value":{"$bindState":"/form/answer"},"items":[{"id":"c","label":"Changelog"},{"id":"r","label":"Rollback"}],"verdicts":[{"id":"ok","label":"Confirmed"},{"id":"no","label":"Cannot confirm","requiresNote":true}]}}}}"#)
        let form = try XCTUnwrap(meta.form)
        var value = ItemReviewAnswer.setting(.null, item: "c", verdict: "ok", note: nil)
        value = ItemReviewAnswer.setting(value, item: "r", verdict: "no", note: nil)
        XCTAssertFalse(form.isComplete(value))
        value = ItemReviewAnswer.setting(value, item: "r", verdict: nil, note: "Old schema")
        XCTAssertTrue(form.isComplete(value))
        XCTAssertEqual(form.summary(value), "Changelog: Confirmed\nRollback: Cannot confirm (Old schema)")
    }

    func testAnOptionAskWithAStrayFormKeepsItsButtons() throws {
        let meta = try metadata(#"{"options":["A","B"],"form":{"catalogVersion":2,"input":{"type":"RankedChoice","props":{"label":"Order","value":{"$bindState":"/form/answer"},"options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}}}}"#)
        XCTAssertNil(meta.form)
    }

    func testSizeLimitCountsSlashesAsJavaScriptDoes() throws {
        let items = (0..<10).map { #"{"id":"i\#($0)","label":"Item \#($0)"}"# }.joined(separator: ",")
        let json = #"{"options":[],"form":{"catalogVersion":2,"input":{"type":"ItemReview","props":{"label":"Checks","value":{"$bindState":"/form/answer"},"items":["# + items + #"],"verdicts":[{"id":"ok","label":"OK"},{"id":"no","label":"No"}]}}}}"#
        let form = try XCTUnwrap(try metadata(json).form)
        let note = String(repeating: "/", count: 900)
        let value = PanelValue.object(Dictionary(uniqueKeysWithValues: (0..<10).map {
            ("i\($0)", PanelValue.object(["verdict": .string("ok"), "note": .string(note)]))
        }))
        XCTAssertTrue(form.fitsSizeLimit(value), "ten valid 900-slash notes are about 9.3 KB, not 18.3 KB")
    }

    func testIgnoresCatalogV1AndReadsReplyAnswers() throws {
        let v1 = try metadata(#"{"options":[],"form":{"catalogVersion":1,"input":{"type":"RankedChoice","props":{}}}}"#)
        XCTAssertNil(v1.form)
        let reply = try metadata(#"{"options":[],"answers":["b","a"]}"#)
        XCTAssertEqual(reply.answers, .array([.string("b"), .string("a")]))
    }

    func testTheSignedReplyCarriesTheAnswers() throws {
        let signer = TestSigner()
        let jws = try BossMessageJWS.signedReply(body: "1. Beta", parentMessageID: "p", provider: signer,
            answers: .array([.string("b")]))
        let payload = try XCTUnwrap(jws.split(separator: ".").dropFirst().first)
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        let json = try XCTUnwrap(String(data: XCTUnwrap(Data(base64Encoded: base64)), encoding: .utf8))
        XCTAssertTrue(json.contains(#""answers":["b"]"#), json)
    }
}

private struct TestSigner: BossMessageSignatureProvider {
    let keyID = "key"
    let bossID = "boss"
    func signature(for data: Data) throws -> Data { Data([1, 2, 3]) }
}
