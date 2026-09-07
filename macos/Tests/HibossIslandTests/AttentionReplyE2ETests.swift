// Exercises attention replies through the draft controller, flow store, and API boundary.
// Exports: AttentionReplyE2ETests covering custom replies, failures, and draft isolation.
// Dependencies: XCTest, HibossKit, ScriptedBossAPI, AttentionReplyState.

import XCTest
import HibossKit
@testable import HibossIsland

@MainActor
final class AttentionReplyE2ETests: XCTestCase {
    func testCustomReplyTargetsSelectedHistoryMessageAndClearsOnlyItsDraft() async {
        let api = ScriptedBossAPI(messages: [])
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["selected"] = "  Please retry after fixing the config.\n  "
        reply.drafts["another"] = "Keep this draft"

        await reply.send(reply.drafts["selected"] ?? "", for: "selected") { text, id in
            await flow.answerHistory(text, for: id)
        }

        let recorded = await api.recordedReplies
        XCTAssertEqual(recorded, [RecordedReply(
            messageID: "selected", choice: "Please retry after fixing the config."
        )])
        XCTAssertNil(reply.drafts["selected"])
        XCTAssertEqual(reply.drafts["another"], "Keep this draft")
        XCTAssertNil(reply.errors["selected"])
        XCTAssertTrue(reply.submitting.isEmpty)
    }

    func testFailedReplyKeepsDraftAndOffersVisibleError() async {
        let api = ScriptedBossAPI(messages: [], replyError: .rejected)
        let flow = OptionFlowStore()
        flow.connect(api: api)
        defer { flow.disconnect() }
        let reply = AttentionReplyState()
        reply.drafts["failed"] = "Please investigate first"

        await reply.send("Please investigate first", for: "failed") { text, id in
            await flow.answerHistory(text, for: id)
        }

        XCTAssertEqual(reply.drafts["failed"], "Please investigate first")
        XCTAssertNotNil(reply.errors["failed"])
        XCTAssertTrue(reply.submitting.isEmpty)
    }

    func testBlankReplyNeverReachesTheAPI() async {
        let reply = AttentionReplyState()
        await reply.send(" \n ", for: "blank") { _, _ in
            XCTFail("Whitespace must not be sent")
            return true
        }
        XCTAssertTrue(reply.submitting.isEmpty)
    }

    func testDuplicateSubmissionIsIgnoredWhileRequestIsPending() async {
        let reply = AttentionReplyState()
        await reply.send("Ship", for: "pending") { _, _ in
            XCTAssertTrue(reply.submitting.contains("pending"))
            await reply.send("Ship", for: "pending") { _, _ in
                XCTFail("An in-flight reply must not be submitted twice")
                return true
            }
            return true
        }
        XCTAssertTrue(reply.submitting.isEmpty)
    }
}
